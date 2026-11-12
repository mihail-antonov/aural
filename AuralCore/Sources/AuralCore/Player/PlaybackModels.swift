import Foundation

// Source-independent playback models. Both the Soloist source and (later) the
// Local source produce these, so the UI never sees Soloist-specific types.
// All of them are small value types (`struct` / `enum`): copying them is cheap
// and they are `Sendable`, so they can be passed between actors safely.

public struct Track: Sendable, Equatable {
    public let id: String
    public let title: String
    public let artists: [String]
    public let album: String?
    /// Cover art sized for the mini player (~300 px), if known.
    public let artworkURL: URL?
    public let durationMs: Int

    public init(id: String, title: String, artists: [String], album: String?, artworkURL: URL?, durationMs: Int) {
        self.id = id
        self.title = title
        self.artists = artists
        self.album = album
        self.artworkURL = artworkURL
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

    public init() {}
}

public enum PlaybackEvent: Sendable, Equatable {
    /// The full state after any change. Sources merge partial updates and always
    /// send the complete (small) state, so the UI only has one case to handle.
    case stateChanged(PlaybackState)
    case loginChanged(isLoggedIn: Bool)
    /// A command was rejected or something went wrong; the message is for logs / UI.
    case error(String)
}
