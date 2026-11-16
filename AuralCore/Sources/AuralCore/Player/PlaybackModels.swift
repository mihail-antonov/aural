import Foundation

// Playback models the UI works with. The Soloist source maps its messages to
// these, so the UI never sees Soloist-specific types.
// All of them are small value types (`struct` / `enum`): copying them is cheap
// and they are `Sendable`, so they can be passed between actors safely.

/// `Codable` so the last track can be saved and restored on the next launch.
public struct Track: Sendable, Equatable, Codable {
    public let id: String
    public let title: String
    public let artists: [String]
    public let album: String?
    /// Cover art sized for the mini player (~300 px), if known.
    public let artworkURL: URL?
    /// Small cover for list rows (~64 px), if known.
    public let thumbnailURL: URL?
    public let durationMs: Int

    public init(id: String, title: String, artists: [String], album: String?, artworkURL: URL?, thumbnailURL: URL? = nil, durationMs: Int) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.artworkURL = artworkURL
        self.thumbnailURL = thumbnailURL
        self.durationMs = durationMs
    }
}

public enum PlaybackStatus: String, Sendable, Equatable {
    case idle, playing, paused, buffering
}

public enum RepeatMode: String, Sendable, Equatable {
    case off, context, track
}

/// Playback position as an anchor: "at `timestamp` we were at `positionMs`,
/// advancing at `speed`". The current position is computed locally, so no
/// per-second events are needed.
public struct PlaybackPosition: Sendable, Equatable {
    public let positionMs: Int
    public let timestamp: Date
    /// 1.0 while playing, 0.0 while paused.
    public let speed: Double

    public init(positionMs: Int, timestamp: Date, speed: Double) {
        self.positionMs = positionMs
        self.timestamp = timestamp
        self.speed = speed
    }

    public static let zero = PlaybackPosition(positionMs: 0, timestamp: .distantPast, speed: 0)

    /// Estimated position at `date`, never below 0 and never past `durationMs` (if given).
    public func current(at date: Date = .now, durationMs: Int? = nil) -> Int {
        let elapsedMs = date.timeIntervalSince(timestamp) * 1000 * speed
        let estimate = max(0, positionMs + Int(elapsedMs))
        guard let durationMs, durationMs > 0 else { return estimate }
        return min(estimate, durationMs)
    }
}

/// Controls the source currently allows. The UI enables buttons from this set
/// instead of assuming every command works (e.g. shuffle is unavailable when a
/// single track is playing).
public enum PlaybackAction: String, Sendable, Hashable, CaseIterable {
    case play, pause, seek, skipNext, skipPrevious, shuffle, setRepeat, addToQueue
}

public struct PlaybackState: Sendable, Equatable {
    public var status: PlaybackStatus = .idle
    public var track: Track?
    public var position: PlaybackPosition = .zero
    /// 0–100.
    public var volume: Int = 0
    public var shuffle = false
    public var repeatMode: RepeatMode = .off
    public var availableActions: Set<PlaybackAction> = []
    /// True when this device is the one Spotify is playing on.
    public var isActiveDevice = false
    /// Name of what is playing, e.g. a playlist or album name. Nil for a
    /// single track or when the source does not know it.
    public var contextName: String?

    public init() {}
}

/// One upcoming track in the queue.
public struct QueueEntry: Sendable, Equatable, Identifiable {
    public enum Source: Sendable, Equatable {
        /// The rest of a list Aural is playing (Liked Songs, a playlist's or
        /// album's tracks, search results).
        case list
        /// The playing playlist or album, as the source plays it.
        case context
        /// Added with "add to queue".
        case queue
        /// Similar songs Spotify picked to keep the music going.
        case autoplay
    }

    /// Unique within one queue (the same song can be queued twice).
    public let id: String
    public let track: Track
    public let source: Source

    public init(id: String, track: Track, source: Source) {
        self.id = id
        self.track = track
        self.source = source
    }
}

/// What plays after the current track.
public struct PlaybackQueue: Sendable, Equatable {
    /// Next first. Bounded by the source (Soloist reports at most 10 of its
    /// own entries; Aural's lists show at most `PlaybackQueue.limit`).
    public var upNext: [QueueEntry] = []
    /// Whether `PlaybackSource.jump(toQueueEntry:)` can start an entry.
    public var canJump = false

    public static let limit = 50

    public init(upNext: [QueueEntry] = [], canJump: Bool = false) {
        self.upNext = upNext
        self.canJump = canJump
    }

    /// Whether `PlaybackSource.clearQueue()` would remove anything: queued
    /// songs and the rest of a list. The playing playlist / album and
    /// autoplay stay, as in Spotify.
    public var canClear: Bool {
        upNext.contains { $0.source == .list || $0.source == .queue }
    }
}

public enum PlaybackEvent: Sendable, Equatable {
    /// The full state after any change. Sources merge partial updates and always
    /// send the complete (small) state, so the UI only has one case to handle.
    case stateChanged(PlaybackState)
    /// The upcoming tracks changed. Separate from `stateChanged`, so the
    /// player does not redraw when only the queue changed.
    case queueChanged(PlaybackQueue)
    case loginChanged(isLoggedIn: Bool)
    /// The service refused a login attempt (for Soloist: the API key is invalid).
    case loginRejected
    /// The playback engine stopped unexpectedly; the message is for logs / UI.
    case sourceStopped(String)
    /// The playback engine is too old to run and must be updated (for
    /// Soloist: the build expired, exit code 10).
    case updateRequired
    /// A command was rejected or something went wrong; the message is for logs / UI.
    case error(String)
}
