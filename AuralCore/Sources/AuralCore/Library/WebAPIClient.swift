import Foundation

public enum WebAPIError: Error, Equatable {
    /// The user must sign in again (refresh token expired or revoked).
    case reauthorizationRequired
    /// 403: e.g. items of a playlist the user does not own, or a user not on
    /// the app's Development Mode allowlist.
    case forbidden(String)
    case notFound
    case rateLimited
    case http(status: Int, message: String)
    case invalidResponse(String)
    case network(String)
}

extension WebAPIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .reauthorizationRequired: "Your Spotify login has expired. Please sign in again."
        case .forbidden(let message): "Spotify does not allow this (\(message))."
        case .notFound: "Not found on Spotify."
        case .rateLimited: "Spotify is limiting requests right now. Please try again in a moment."
        case .http(let status, let message): "Spotify error \(status): \(message)"
        case .invalidResponse(let reason): "Unexpected response from Spotify: \(reason)"
        case .network(let reason): "Could not reach Spotify: \(reason)"
        }
    }
}

/// Authorized requests to the Spotify Web API. Refreshes the access token
/// when needed and reports new tokens through `onTokensChanged` (for storage).
public actor WebAPIClient {
    static let baseURL = URL(string: "https://api.spotify.com/v1")! // constant literal

    private let auth: SpotifyAuth
    private var tokens: SpotifyTokens
    private let onTokensChanged: @Sendable (SpotifyTokens) -> Void
    private let session: URLSession

    public init(auth: SpotifyAuth, tokens: SpotifyTokens, onTokensChanged: @escaping @Sendable (SpotifyTokens) -> Void = { _ in }) {
        self.auth = auth
        self.tokens = tokens
        self.onTokensChanged = onTokensChanged
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil // responses are decoded into small structs, never kept
        session = URLSession(configuration: configuration)
    }

    /// GET and decode JSON.
    public func get<Response: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: Response.Type = Response.self
    ) async throws(WebAPIError) -> Response {
        let data = try await perform("GET", path, query: query)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw .invalidResponse(String(describing: error))
        }
    }

    /// PUT / DELETE without a response body (e.g. `/me/library`).
    public func send(_ method: String, _ path: String, query: [URLQueryItem] = []) async throws(WebAPIError) {
        _ = try await perform(method, path, query: query)
    }

    /// Status code only, for the developer endpoint check.
    public func status(_ method: String, _ path: String, query: [URLQueryItem] = []) async -> Int {
        do {
            _ = try await perform(method, path, query: query)
            return 200
        } catch {
            switch error {
            case .forbidden: return 403
            case .notFound: return 404
            case .rateLimited: return 429
            case .http(let status, _): return status
            case .reauthorizationRequired: return 401
            case .invalidResponse, .network: return -1
            }
        }
    }

    // MARK: - Request

    private func perform(_ method: String, _ path: String, query: [URLQueryItem], isRetry: Bool = false) async throws(WebAPIError) -> Data {
        if tokens.needsRefresh() { try await refreshTokens() }

        var components = URLComponents(url: Self.baseURL.appending(path: path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw .invalidResponse("bad URL for \(path)") }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(tokens.accessToken)", forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw .network(error.localizedDescription)
        }
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0

        switch status {
        case 200...299:
            return data
        case 401 where !isRetry:
            // Token revoked or expired early: refresh once and retry.
            try await refreshTokens()
            return try await perform(method, path, query: query, isRetry: true)
        case 401:
            throw .reauthorizationRequired
        case 403:
            throw .forbidden(Self.message(from: data))
        case 404:
            throw .notFound
        case 429 where !isRetry:
            // Wait as long as Spotify asks (capped), then retry once.
            let seconds = min(Double(http?.value(forHTTPHeaderField: "Retry-After") ?? "") ?? 2, 30)
            try? await Task.sleep(for: .seconds(seconds))
            return try await perform(method, path, query: query, isRetry: true)
        case 429:
            throw .rateLimited
        default:
            throw .http(status: status, message: Self.message(from: data))
        }
    }

    private func refreshTokens() async throws(WebAPIError) {
        do {
            tokens = try await auth.refresh(tokens)
            onTokensChanged(tokens)
        } catch .reauthorizationRequired {
            throw .reauthorizationRequired
        } catch {
            throw .network(error.localizedDescription)
        }
    }

    /// Spotify errors look like `{"error":{"status":403,"message":"…"}}`.
    private static func message(from data: Data) -> String {
        struct Body: Decodable { struct Inner: Decodable { let message: String? }; let error: Inner? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error?.message
            ?? String(decoding: data.prefix(200), as: UTF8.self)
    }
}
