import Foundation

/// The user's Soloist API key from the Spotify for Developers dashboard.
///
/// Soloist accepts any key at startup; Spotify only rejects an invalid key when
/// a phone tries to pair. So this is a loose sanity check that catches paste
/// mistakes, not real validation. The key format is undocumented (keys seen so
/// far: 37 characters of letters, digits and `_`), so the rules stay generous.
public enum SoloistAPIKey {
    /// Page where the user generates their key.
    public static let dashboardURL = URL(string: "https://developer.spotify.com/dashboard/soloist")! // constant literal

    public enum FormatError: Error, Equatable, LocalizedError {
        case empty
        case containsWhitespace
        case unexpectedCharacters
        case unexpectedLength

        public var errorDescription: String? {
            switch self {
            case .empty: "Paste your API key."
            case .containsWhitespace: "The key contains spaces or line breaks. Copy only the key itself."
            case .unexpectedCharacters: "This does not look like a Soloist API key. Copy it again from the dashboard."
            case .unexpectedLength: "This key looks too short or too long. Copy it again from the dashboard."
            }
        }
    }

    /// Returns the cleaned-up key (surrounding whitespace removed) or why it looks wrong.
    public static func normalize(_ input: String) throws(FormatError) -> String {
        let key = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw .empty }
        guard !key.contains(where: \.isWhitespace) else { throw .containsWhitespace }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-"))
        guard key.unicodeScalars.allSatisfy({ $0.isASCII && allowed.contains($0) }) else { throw .unexpectedCharacters }
        guard (16...256).contains(key.count) else { throw .unexpectedLength }
        return key
    }
}
