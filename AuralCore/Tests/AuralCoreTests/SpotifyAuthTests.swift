import Foundation
import Testing
@testable import AuralCore

struct SpotifyAuthTests {
    /// Test vector from RFC 7636, appendix B.
    @Test func codeChallengeMatchesRFC7636() {
        #expect(SpotifyAuth.codeChallenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
            == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func codeVerifierHasAllowedLengthAndCharacters() {
        let verifier = SpotifyAuth.makeCodeVerifier()
        #expect((43...128).contains(verifier.count))
        #expect(verifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) })
        #expect(verifier != SpotifyAuth.makeCodeVerifier())
    }

    @Test func authorizationURLHasPKCEParameters() throws {
        let url = SpotifyAuth(clientID: " abc123 ").authorizationURL(codeChallenge: "CHALLENGE", state: "STATE")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.host() == "accounts.spotify.com")
        #expect(query["client_id"] == "abc123")
        #expect(query["response_type"] == "code")
        #expect(query["redirect_uri"] == "http://127.0.0.1:43821/callback")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["code_challenge"] == "CHALLENGE")
        #expect(query["state"] == "STATE")
        #expect(query["scope"] == "playlist-read-private playlist-read-collaborative user-library-read user-library-modify")
    }

    @Test func formEncodingEscapesReservedCharacters() {
        #expect(SpotifyAuth.formEncode(["redirect_uri": "http://127.0.0.1:43821/callback", "a": "x y&z"])
            == "a=x%20y%26z&redirect_uri=http%3A%2F%2F127.0.0.1%3A43821%2Fcallback")
    }

    @Test func tokensRefreshOneMinuteEarly() {
        let now = Date(timeIntervalSince1970: 1_000)
        let tokens = SpotifyTokens(accessToken: "a", refreshToken: "r", expiresAt: now.addingTimeInterval(120), scope: "")
        #expect(!tokens.needsRefresh(at: now))
        #expect(tokens.needsRefresh(at: now.addingTimeInterval(61)))
    }
}
