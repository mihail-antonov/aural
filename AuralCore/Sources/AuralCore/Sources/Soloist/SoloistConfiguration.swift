import Foundation

/// Where Soloist lives and how Aural launches it.
///
/// `defaultExecutableURL` is the single source of truth for the Soloist
/// executable path. Nothing else in Aural hard-codes it.
public struct SoloistConfiguration: Sendable {
    /// Aural's own Soloist install: `~/Library/Application Support/Aural/soloist/soloist`.
    /// (In-app install/update comes in Stage 7; until then use an override.)
    public static var defaultExecutableURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Aural/soloist/soloist", directoryHint: .notDirectory)
    }

    /// Soloist's own default data directory (device identity, pairing session,
    /// `soloist.pid`, `ws.addr`, `ws.port`). Kept separate from the executable
    /// so that updates keep the pairing.
    public static var defaultDataDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "soloist", directoryHint: .isDirectory)
    }

    /// Keychain service name of the user's Soloist API key.
    public static let apiKeyKeychainService = "aural-soloist-api-key"

    public var executableURL: URL
    public var dataDirectory: URL
    /// Name shown in the Spotify Connect device picker.
    public var deviceName: String
    /// Cap for Soloist's playback cache. Soloist's default is unlimited; minimum 100.
    public var cacheSizeMB: Int
    /// How long to wait for Soloist's WebSocket server after launch.
    public var startTimeout: Duration

    public init(
        executableURL: URL? = nil,
        dataDirectory: URL? = nil,
        deviceName: String = "Aural",
        cacheSizeMB: Int = 100,
        startTimeout: Duration = .seconds(15)
    ) {
        self.executableURL = executableURL ?? Self.defaultExecutableURL
        self.dataDirectory = dataDirectory ?? Self.defaultDataDirectory
        self.deviceName = deviceName
        self.cacheSizeMB = cacheSizeMB
        self.startTimeout = startTimeout
    }
}

public enum SoloistStartMode: Sendable, Equatable {
    /// Aural launched Soloist and stops it on quit.
    case launched
    /// Soloist was already running with the same data directory; Aural leaves it running.
    case attached(pid: Int32)
}
