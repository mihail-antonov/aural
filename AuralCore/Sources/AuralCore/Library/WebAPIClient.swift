import Foundation

public enum WebAPIError: Error, Equatable {
    /// The user must sign in again (refresh token expired or revoked).
    case reauthorizationRequired
    /// 403: e.g. items of a playlist the user does not own, or a user not on
    /// the app's Development Mode allowlist.
    case forbidden(String)
    case notFound
    /// 429. Spotify asked Aural to wait until this time.
    case rateLimited(until: Date)
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
        case .rateLimited(let until): "Spotify is limiting requests. Please try again in \(Self.describeWait(until: until))."
        case .http(let status, let message): "Spotify error \(status): \(message)"
        case .invalidResponse(let reason): "Unexpected response from Spotify: \(reason)"
        case .network(let reason): "Could not reach Spotify: \(reason)"
        }
    }

    /// "40 seconds", "3 minutes", "2 hours" from now (rounded up).
    static func describeWait(until date: Date, now: Date = .now) -> String {
        let seconds = max(1, Int(date.timeIntervalSince(now).rounded(.up)))
        func plural(_ count: Int, _ unit: String) -> String { "\(count) \(unit)\(count == 1 ? "" : "s")" }
        if seconds < 60 { return plural(seconds, "second") }
        if seconds < 3600 { return plural((seconds + 59) / 60, "minute") }
        return plural((seconds + 3599) / 3600, "hour")
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
    /// Set by a 429: until then every request fails right away instead of
    /// asking again. (Requests during a rate limit can make Spotify extend it.)
    private var blockedUntil: Date?

    /// Short waits are sat out and the request retried; longer ones fail at
    /// once, so the UI shows the error instead of a spinner.
    static let maxRetryWait = 5.0

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
        if let blockedUntil, blockedUntil > .now { throw .rateLimited(until: blockedUntil) }
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
        case 429:
            let seconds = Self.retryAfter(http?.value(forHTTPHeaderField: "Retry-After"))
            Log.webAPI.notice("429 for \(path, privacy: .public): Retry-After \(seconds, privacy: .public) s")
            if !isRetry, seconds <= Self.maxRetryWait {
                try? await Task.sleep(for: .seconds(seconds))
                return try await perform(method, path, query: query, isRetry: true)
            }
            let until = Date.now + seconds
            blockedUntil = max(blockedUntil ?? until, until)
            throw .rateLimited(until: until)
        case 502...504 where !isRetry:
            // Spotify's servers are briefly unavailable (seen when several
            // library requests run at once). Every Aural request is safe to
            // repeat (GET, or PUT/DELETE of the same items), so retry once.
            try? await Task.sleep(for: .seconds(1))
            return try await perform(method, path, query: query, isRetry: true)
        default:
            let message = Self.message(from: data)
            throw .http(status: status, message: message.isEmpty ? HTTPURLResponse.localizedString(forStatusCode: status) : message)
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

    /// Seconds from a `Retry-After` header; 2 if it is missing or unreadable.
    static func retryAfter(_ header: String?) -> Double {
        guard let header, let seconds = Double(header.trimmingCharacters(in: .whitespaces)), seconds >= 0 else { return 2 }
        return seconds
    }

    /// Spotify errors look like `{"error":{"status":403,"message":"…"}}`.
    private static func message(from data: Data) -> String {
        struct Body: Decodable { struct Inner: Decodable { let message: String? }; let error: Inner? }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error?.message
            ?? String(decoding: data.prefix(200), as: UTF8.self)
    }
}
