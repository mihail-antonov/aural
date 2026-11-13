/// Plays a list of tracks (Liked Songs, a playlist's or album's tracks, search
/// results) from a chosen track on top of Soloist.
///
/// Soloist's `play` cannot start a playlist or album at a given track, and
/// there is no `play` for Liked Songs at all, so Aural plays the chosen track
/// and queues what follows. Soloist's queue cannot be cleared, though: tracks
/// queued for one list would still play after the user picked another one
/// (tested: neither `play` nor `deactivate` clears it). So Aural keeps only the
/// **next** track of the list in Soloist's queue and adds the following one
/// each time it starts. A track Aural queued for a list that is no longer
/// playing is "stale": if it starts, Aural skips it right away.
///
/// Pure value type (no I/O), so the rules are unit-tested; `SoloistSource`
/// carries out the returned actions.
struct SoloistListQueue {
    enum Action: Equatable {
        case addToQueue(String)
        /// A stale track started: skip to the next one.
        case skip
    }

    /// Longest list kept, so memory stays bounded (URIs are ~40 bytes).
    static let capacity = 1_000
    /// Stale tracks remembered; more are never waiting in practice.
    static let staleCapacity = 20

    private(set) var uris: [String] = []
    /// Position of the playing track in `uris`.
    private(set) var index = 0
    /// The list's next track, added to Soloist's queue and not started yet.
    private(set) var queued: String?
    /// Tracks Aural queued for earlier lists that may still be in Soloist's queue.
    private(set) var stale: [String] = []
    /// The track just sent with `play`: when it starts it is never "stale",
    /// even if an older copy of it is waiting in the queue.
    private var expected: String?

    /// Starts `uris[index]`. Returns the track to play and the one to queue.
    mutating func start(_ newURIs: [String], at newIndex: Int) -> (play: String, queue: String?)? {
        guard newURIs.indices.contains(newIndex) else { return nil }
        markQueuedStale()
        // Keep at most `capacity` tracks around the starting point.
        let lower = max(0, newIndex - Self.capacity / 2)
        let upper = min(newURIs.count, lower + Self.capacity)
        uris = Array(newURIs[lower..<upper])
        index = newIndex - lower
        expected = uris[index]
        queued = uris.indices.contains(index + 1) ? uris[index + 1] : nil
        return (uris[index], queued)
    }

    /// Restarts the list one track back (for "previous").
    mutating func startPrevious() -> (play: String, queue: String?)? {
        guard index > 0 else { return nil }
        return start(uris, at: index - 1)
    }

    /// The list's tracks after the current one.
    var upcoming: ArraySlice<String> {
        uris.indices.contains(index + 1) ? uris[(index + 1)...] : []
    }

    /// Whether Aural will skip `uri` when it starts (queued for an earlier list).
    func isStale(_ uri: String) -> Bool {
        stale.contains(uri)
    }

    /// Whether `uri` is the list's current track (so "previous" means the
    /// list's previous track, not autoplay's or another list's).
    func isPlaying(_ uri: String?) -> Bool {
        guard let uri, uris.indices.contains(index) else { return false }
        return uris[index] == uri
    }

    /// Tracks waiting in Soloist's queue that should not play: they are
    /// skipped when they start (Soloist's queue cannot be cleared).
    mutating func skipWhenStarted(_ uris: [String]) {
        for uri in uris where !stale.contains(uri) { stale.append(uri) }
        if stale.count > Self.staleCapacity { stale.removeFirst(stale.count - Self.staleCapacity) }
    }

    /// Something else is played (a playlist or album as a whole), or the
    /// rest of the list was cleared from the queue.
    mutating func stop() {
        markQueuedStale()
        uris = []
        index = 0
        expected = nil
    }

    /// Call when a track starts playing.
    mutating func trackStarted(_ uri: String) -> Action? {
        if uri == expected {
            expected = nil
            return nil
        }
        if let queued, uri == queued {
            index += 1
            self.queued = uris.indices.contains(index + 1) ? uris[index + 1] : nil
            return self.queued.map(Action.addToQueue)
        }
        if let position = stale.firstIndex(of: uri) {
            stale.remove(at: position)
            return .skip
        }
        return nil
    }

    private mutating func markQueuedStale() {
        guard let queued else { return }
        stale.append(queued)
        if stale.count > Self.staleCapacity { stale.removeFirst(stale.count - Self.staleCapacity) }
        self.queued = nil
    }
}
