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
            state.contextName = Self.contextName(snapshot.context)
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
        case .contextChanged(let context):
            state.contextName = Self.contextName(context)
        case .queueChanged, .commandResult, .error, .unknown:
            break
        }
        return state
    }

    /// Playlist / album name. A single track as context has no useful name.
    private static func contextName(_ context: SoloistWire.Entity?) -> String? {
        guard let context, context.entityType != "track", context.entityType != "unknown" else { return nil }
        let name = context.decorations?.identity?.name
        return name?.isEmpty == false ? name : nil
    }

    private mutating func apply(_ options: SoloistWire.Options) {
        shuffle = options.shuffle
        repeatMode = RepeatMode(rawValue: options.repeat) ?? .off
    }
}

extension QueueEntry {
    /// Soloist's upcoming entries as Aural queue entries. Placeholders and
    /// non-track entries (e.g. episodes) are left out.
    static func entries(soloist upcoming: [SoloistWire.QueueEntry]) -> [QueueEntry] {
        upcoming.enumerated().compactMap { offset, entry in
            guard let track = Track(soloist: entry.item), track.id.hasPrefix("spotify:track:") else { return nil }
            let source: Source = switch entry.source {
            case "queue": .queue
            case "autoplay": .autoplay
            default: .context
            }
            return QueueEntry(id: entry.uid ?? "\(offset)-\(track.id)", track: track, source: source)
        }
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
            thumbnailURL: Self.thumbnailURL(from: decorations?.visualIdentity?.cover ?? []),
            durationMs: decorations?.playback?.durationMs ?? 0
        )
    }

    /// Queue rows show the cover at 44 pt: `small` (~64 px) is enough and
    /// decodes to a few KB instead of ~1.6 MB for `large`.
    private static func thumbnailURL(from covers: [SoloistWire.Cover]) -> URL? {
        for size in ["small", "default"] {
            if let cover = covers.first(where: { $0.size == size }), let url = URL(string: cover.url) {
                return url
            }
        }
        return nil
    }

    /// The player shows the cover at 225 pt (450 px on Retina). Soloist's
    /// `default` size is ~300 px, which would look soft, so prefer `large`
    /// (640 px); the app downscales it to 450 px when decoding.
    private static func artworkURL(from covers: [SoloistWire.Cover]) -> URL? {
        let preferred = ["large", "default", "xlarge", "small"]
        for size in preferred {
            if let cover = covers.first(where: { $0.size == size }), let url = URL(string: cover.url) {
                return url
            }
        }
        return covers.first.flatMap { URL(string: $0.url) }
    }
}
