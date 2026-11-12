import Foundation

// Converts Soloist wire types into Aural's source-independent models.
// Pure functions only (no I/O), so they are easy to test.

extension PlaybackState {
    /// Returns the state after applying one Soloist event.
    /// Events that do not affect playback state return `self` unchanged.
    func applying(_ event: SoloistEvent) -> PlaybackState {
        var state = self
        switch event {
        case .playbackState(let snapshot):
            state.status = PlaybackStatus(soloist: snapshot.status)
            state.track = snapshot.item.flatMap(Track.init(soloist:))
            if let position = snapshot.position { state.position = PlaybackPosition(soloist: position) }
            if let volume = snapshot.volume { state.volume = volume }
            if let isActive = snapshot.isActive { state.isActiveDevice = isActive }
            if let options = snapshot.options { state.apply(options) }
            state.availableActions = Set((snapshot.availableActions ?? [:]).keys.compactMap(PlaybackAction.init(soloist:)))
        case .trackChanged(let item):
            state.track = item.flatMap(Track.init(soloist:))
        case .playbackChanged(let status):
            state.status = PlaybackStatus(soloist: status)
        case .positionSync(let position):
            state.position = PlaybackPosition(soloist: position)
        case .volumeChanged(let volume):
            state.volume = volume
        case .optionsChanged(let options):
            state.apply(options)
        case .deviceChanged(let isActive), .authState(_, let isActive):
            state.isActiveDevice = isActive
        case .queueChanged, .contextChanged, .commandResult, .error, .unknown:
            break
        }
        return state
    }

    private mutating func apply(_ options: SoloistWire.Options) {
        shuffle = options.shuffle
        repeatMode = RepeatMode(rawValue: options.repeat) ?? .off
    }
}

extension PlaybackStatus {
    init(soloist status: String) {
        // Unknown future values fall back to `.idle` instead of failing.
        self = PlaybackStatus(rawValue: status) ?? .idle
    }
}

extension PlaybackPosition {
    init(soloist position: SoloistWire.Position) {
        self.init(
            positionMs: position.positionMs,
            timestamp: Date(timeIntervalSince1970: Double(position.timestampMs) / 1000),
            speed: position.speed
        )
    }
}

extension PlaybackAction {
    init?(soloist name: String) {
        switch name {
        case "play": self = .play
        case "pause": self = .pause
        case "seek": self = .seek
        case "skip_next": self = .skipNext
        case "skip_prev": self = .skipPrevious
        case "shuffle": self = .shuffle
        case "set_repeat": self = .setRepeat
        case "add_to_queue": self = .addToQueue
        default: return nil // e.g. seek_forward / seek_backward, not used by Aural
        }
    }
}

extension Track {
    /// Builds a track from a Soloist entity. Returns nil for entities without a
    /// URI or name (Soloist uses placeholder entities in some messages).
    init?(soloist entity: SoloistWire.Entity) {
        guard let uri = entity.uri, !uri.isEmpty,
              let title = entity.decorations?.identity?.name
        else { return nil }

        let decorations = entity.decorations
        self.init(
            id: uri,
            title: title,
            artists: (decorations?.creators ?? []).compactMap { $0.entity.decorations?.identity?.name },
            album: decorations?.parent?.entity.decorations?.identity?.name,
            artworkURL: Self.artworkURL(from: decorations?.visualIdentity?.cover ?? []),
            durationMs: decorations?.playback?.durationMs ?? 0
        )
    }

    /// The mini player shows ~110 pt art (220 px on Retina). Soloist's
    /// `default` size is ~300 px, so prefer it over `large` (640 px) to keep
    /// downloads and decoded images small.
    private static func artworkURL(from covers: [SoloistWire.Cover]) -> URL? {
        let preferred = ["default", "large", "xlarge", "small"]
        for size in preferred {
            if let cover = covers.first(where: { $0.size == size }), let url = URL(string: cover.url) {
                return url
            }
        }
        return covers.first.flatMap { URL(string: $0.url) }
    }
}
