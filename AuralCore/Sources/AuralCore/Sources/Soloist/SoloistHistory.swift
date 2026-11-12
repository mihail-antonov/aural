/// Spotify-style "previous track" on top of Soloist.
///
/// Soloist's `skip_prev` only knows the current context. That works inside a
/// playlist or album, but not when Aural played a single track and queued the
/// rest of a list, or when autoplay took over: then it jumps to a track the
/// user never heard. So Aural remembers which tracks actually played and goes
/// back to the previous one itself.
///
/// Pure value type (no I/O), so the rules are unit-tested; `SoloistSource`
/// feeds it events and carries out the returned action.
struct SoloistHistory {
    enum PreviousAction: Equatable {
        /// Seek to the start of the current track.
        case restart
        /// Let Soloist go back within its playlist / album context.
        case skipInContext
        /// Play this track URI. The tracks that followed are queued again once
        /// Soloist reports the new queue (see `tracksToRequeue`).
        case play(uri: String)
    }

    /// Like Spotify: after this point, "previous" restarts the current track.
    static let restartThresholdMs = 3_000
    /// Bounded, so the history never grows without limit.
    static let capacity = 50

    /// Track URIs in the order they started, oldest first.
    private(set) var played: [String] = []
    /// Track URIs the user queued (`add_to_queue`), next first, from the latest
    /// `queue_changed`. Broadcasts carry at most 10 entries.
    private var upcomingQueued: [String] = []
    /// While going back: the target track and what to queue after it.
    private var pendingRequeue: (target: String, uris: [String])?

    mutating func trackStarted(_ uri: String) {
        if let pending = pendingRequeue, pending.target != uri { pendingRequeue = nil }
        guard played.last != uri else { return }
        played.append(uri)
        if played.count > Self.capacity { played.removeFirst(played.count - Self.capacity) }
    }

    /// Decides what "previous" does. `contextType` is Soloist's `entity_type`
    /// of the current context (`album`, `playlist`, `track`, …).
    mutating func previous(currentURI: String?, positionMs: Int, contextType: String?) -> PreviousAction {
        if contextType == "album" || contextType == "playlist" { return .skipInContext }
        guard positionMs < Self.restartThresholdMs,
              let currentURI, played.last == currentURI, played.count >= 2
        else { return .restart }

        played.removeLast()
        // The target stays in `played`: when it starts again it is not added twice.
        let target = played[played.count - 1]
        pendingRequeue = (target, [currentURI] + upcomingQueued)
        return .play(uri: target)
    }

    /// Call on every `queue_changed`. Returns the tracks to add to the queue
    /// after going back: the track the user left and the rest of their queue.
    /// Empty if Soloist kept its queue (then re-adding would duplicate tracks).
    mutating func tracksToRequeue(upcoming: [SoloistWire.QueueEntry], currentURI: String?) -> [String] {
        upcomingQueued = upcoming.compactMap { entry in
            guard entry.source == "queue", let uri = entry.item.uri, uri.hasPrefix("spotify:track:") else { return nil }
            return uri
        }
        // Wait until Soloist has switched to the target track.
        guard let pending = pendingRequeue, pending.target == currentURI else { return [] }
        pendingRequeue = nil
        return upcomingQueued.isEmpty ? pending.uris : []
    }
}
