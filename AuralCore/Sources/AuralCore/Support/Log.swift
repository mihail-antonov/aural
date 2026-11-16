import os

/// Loggers for AuralCore. View them in Console.app or with
/// `log stream --predicate 'subsystem == "app.aural"'`.
/// Never log API keys or tokens.
enum Log {
    static let soloist = Logger(subsystem: "app.aural", category: "soloist")
    /// Soloist's own stdout/stderr, forwarded line by line.
    static let soloistOutput = Logger(subsystem: "app.aural", category: "soloist-output")
    static let webAPI = Logger(subsystem: "app.aural", category: "web-api")
    static let cache = Logger(subsystem: "app.aural", category: "cache")
    static let keychain = Logger(subsystem: "app.aural", category: "keychain")
}
