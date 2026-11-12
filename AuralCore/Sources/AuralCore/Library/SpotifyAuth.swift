import CryptoKit
import Foundation

/// Spotify Web API login with OAuth "Authorization Code with PKCE".
///
/// PKCE needs no client secret: Aural proves it started the login by sending
/// the SHA-256 hash of a random "verifier" first and the verifier itself later.
/// Each user registers their own app in the Spotify dashboard (Development
/// Mode), so the Client ID is entered in setup rather than built in.
/// Reference: https://developer.spotify.com/documentation/web-api/tutorials/code-pkce-flow
public struct SpotifyAuth: Sendable {
    /// Must match the redirect URI registered in the user's Spotify app exactly.
    /// Loopback + http is allowed by Spotify; the dashboard requires a port.
    public static let redirectPort: UInt16 = 43821
    public static let redirectPath = "/callback"
    public static var redirectURI: String { "http://127.0.0.1:\(redirectPort)\(redirectPath)" }

    /// Where users create their app and find the Client ID.
    public static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard")! // constant literal

    /// Only what Aural uses: read playlists (own + collaborative), read and
    /// change Liked Songs / saved albums. Search needs no scope.
    public static let scopes = [
        "playlist-read-private",
        "playlist-read-collaborative",
        "user-library-read",
        "user-library-modify",
    ]

    // Constant, valid URL literals.
    static let authorizeURL = URL(string: "https://accounts.spotify.com/authorize")!
    static let tokenURL = URL(string: "https://accounts.spotify.com/api/token")!

    public let clientID: String

    public init(clientID: String) {
        self.clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Full login: opens the browser via `openURL`, waits for the redirect to
    /// 127.0.0.1, then exchanges the code for tokens.
    public func login(
        timeout: Duration = .seconds(300),
        openURL: @Sendable (URL) async -> Void
    ) async throws(SpotifyAuthError) -> SpotifyTokens {
        let verifier = Self.makeCodeVerifier()
        let state = Self.randomString(length: 32)
        let server = LoopbackServer(port: Self.redirectPort, path: Self.redirectPath)

        // Start listening before the browser can redirect.
        async let callback = server.waitForCallback(timeout: timeout)
        await openURL(authorizationURL(codeChallenge: Self.codeChallenge(for: verifier), state: state))

        let query: [String: String]
        do {
            query = try await callback.query
        } catch let error as SpotifyAuthError {
            throw error
        } catch {
            throw .network(error.localizedDescription)
        }

        guard query["state"] == state else { throw .stateMismatch }
        if let error = query["error"] { throw error == "access_denied" ? .loginCancelled : .loginDenied(error) }
        guard let code = query["code"] else { throw .loginDenied("no code") }

        return try await requestTokens([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ], previous: nil)
    }

    /// Gets a new access token. Refreshing does not extend the refresh token's
    /// 6-month lifetime; after that `reauthorizationRequired` is thrown.
    public func refresh(_ tokens: SpotifyTokens) async throws(SpotifyAuthError) -> SpotifyTokens {
        try await requestTokens([
            "grant_type": "refresh_token",
            "refresh_token": tokens.refreshToken,
            "client_id": clientID,
        ], previous: tokens)
    }

    func authorizationURL(codeChallenge: String, state: String) -> URL {
        var components = URLComponents(url: Self.authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
        ]
        return components?.url ?? Self.authorizeURL
    }

    // MARK: - Token endpoint

    private func requestTokens(_ form: [String: String], previous: SpotifyTokens?) async throws(SpotifyAuthError) -> SpotifyTokens {
        var request = URLRequest(url: Self.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(Self.formEncode(form).utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw .network(error.localizedDescription)
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = String(decoding: data.prefix(300), as: UTF8.self)
            // An expired or revoked refresh token comes back as `invalid_grant`.
            if previous != nil, body.contains("invalid_grant") { throw .reauthorizationRequired }
            throw .tokenRequestFailed(status: status, message: body)
        }
        guard let token = try? JSONDecoder().decode(TokenResponse.self, from: data),
              let refreshToken = token.refreshToken ?? previous?.refreshToken
        else {
            throw .tokenRequestFailed(status: status, message: "unexpected response")
        }
        return SpotifyTokens(
            accessToken: token.accessToken,
            refreshToken: refreshToken,
            expiresAt: Date.now.addingTimeInterval(TimeInterval(token.expiresIn)),
            scope: token.scope ?? previous?.scope ?? ""
        )
    }

    // MARK: - PKCE helpers

    /// 64 random characters from the allowed set (spec: 43–128).
    static func makeCodeVerifier() -> String {
        randomString(length: 64)
    }

    /// base64url(SHA-256(verifier)) without padding.
    static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// `SystemRandomNumberGenerator` is cryptographically secure on Apple platforms.
    static func randomString(length: Int) -> String {
        let characters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in characters.randomElement(using: &generator) ?? "a" })
    }

    static func formEncode(_ form: [String: String]) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return form.sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)"
            }
            .joined(separator: "&")
    }
}
