import Foundation

/// OAuth tokens for the Spotify Web API. Stored as JSON in the Keychain by the app.
public struct SpotifyTokens: Codable, Sendable, Equatable {
    public var accessToken: String
    public var refreshToken: String
    public var expiresAt: Date
    public var scope: String

    public init(accessToken: String, refreshToken: String, expiresAt: Date, scope: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    /// Refresh a minute early so a request never starts with an about-to-expire token.
    public func needsRefresh(at date: Date = .now) -> Bool {
        date.addingTimeInterval(60) >= expiresAt
    }
}

/// The token endpoint's JSON response.
struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    /// Refresh responses may omit it; then the previous refresh token stays valid.
    let refreshToken: String?
    let scope: String?

    enum CodingKeys: String, CodingKey {
        case scope
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

public enum SpotifyAuthError: Error, Equatable {
    case callbackPortUnavailable(UInt16)
    case loginCancelled
    case loginDenied(String)
    case stateMismatch
    case timedOut
    case tokenRequestFailed(status: Int, message: String)
    /// The refresh token expired or was revoked: the user must sign in again.
    case reauthorizationRequired
    case network(String)
}

extension SpotifyAuthError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .callbackPortUnavailable(let port): "Port \(port) on this Mac is in use by another program, so the Spotify login cannot finish."
        case .loginCancelled: "The Spotify login was cancelled."
        case .loginDenied(let reason): "Spotify did not allow access (\(reason))."
        case .stateMismatch: "The login response did not match this login attempt. Please try again."
        case .timedOut: "The Spotify login took too long. Please try again."
        case .tokenRequestFailed(let status, let message): "Spotify rejected the login (\(status)): \(message)"
        case .reauthorizationRequired: "Your Spotify login has expired. Please sign in again."
        case .network(let reason): "Could not reach Spotify: \(reason)"
        }
    }
}
