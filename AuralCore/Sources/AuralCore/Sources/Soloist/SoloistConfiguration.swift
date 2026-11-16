import Foundation

/// Where Soloist lives and how Aural launches it.
///
/// `defaultExecutableURL` is the single source of truth for the Soloist
/// executable path. Nothing else in Aural hard-codes it.
public struct SoloistConfiguration: Sendable {
    /// Aural's own Soloist install: `~/Library/Application Support/Aural/soloist/soloist`,
    /// installed and updated by `SoloistInstaller`. Tools can pass an override.
    public static var defaultExecutableURL: URL {
        URL.applicationSupportDirectory
            .appending(path: "Aural/soloist/soloist", directoryHint: .notDirectory)
    }

    /// Aural's own Soloist data directory (device identity, pairing session,
    /// `soloist.pid`, `ws.addr`, `ws.port`). Separate from the executable so
    /// updates keep the pairing, and separate from Soloist's default directory
    /// so a Soloist the user runs by hand never clashes with Aural's.
    public static var defaultDataDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Aural/soloist-data", directoryHint: .isDirectory)
    }

    /// Keychain service name of the user's Soloist API key.
    public static let apiKeyKeychainService = "app.aural.soloist-api-key"

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
    /// Soloist was already running with the same data directory (e.g. after a
    /// crash); Aural takes it over and stops it on quit.
    case attached(pid: Int32)
}
