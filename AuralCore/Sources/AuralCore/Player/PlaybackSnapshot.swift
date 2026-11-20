import Foundation

/// What was playing when Aural last quit, so the next launch can show it
/// (paused) and continue where the user left off. Soloist itself forgets
/// its playback when it restarts.
///
/// Small and bounded: one track plus at most `PlaybackQueue.limit` upcoming
/// tracks (~20 KB as JSON).
public struct PlaybackSnapshot: Sendable, Equatable, Codable {
    public var track: Track
    public var positionMs: Int
    /// Playlist / album name for the player's header.
    public var contextName: String?
    /// What followed the track: the rest of a list Aural was playing, or the
    /// playlist / album tracks Soloist had queued. Played after `track`.
    public var upcoming: [Track]
    /// 0–100. Soloist starts at its own volume after every restart, so Aural
    /// gives it back the user's. Nil in files saved before Aural kept it
    /// (an optional property decodes as nil when the key is missing).
    public var volume: Int?

    public init(track: Track, positionMs: Int, contextName: String?, upcoming: [Track], volume: Int? = nil) {
        self.track = track
        self.positionMs = positionMs
        self.contextName = contextName
        self.upcoming = Array(upcoming.prefix(PlaybackQueue.limit))
        self.volume = volume
    }

    /// `~/Library/Application Support/Aural/last-playback.json`.
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory.appending(path: "Aural/last-playback.json", directoryHint: .notDirectory)
    }

    /// The saved snapshot, or nil if there is none or it cannot be read
    /// (e.g. written by an older Aural with a different format).
    public static func load(from file: URL = defaultFileURL) -> PlaybackSnapshot? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(PlaybackSnapshot.self, from: data)
    }

    public func save(to file: URL = Self.defaultFileURL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }
}
