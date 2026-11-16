import Foundation

/// Spotify playback through Soloist. Implements `PlaybackSource`, so the rest
/// of Aural never sees Soloist's message format.
public actor SoloistSource: PlaybackSource {
    /// `nonisolated` lets callers read the stream without `await`: it is
    /// created once in `init` and never changes.
    public nonisolated let events: AsyncStream<PlaybackEvent>
    private nonisolated let continuation: AsyncStream<PlaybackEvent>.Continuation

    private let process: SoloistProcess
    private var connection: SoloistConnection?
    private var listenTask: Task<Void, Never>?
    private var state = PlaybackState()
    /// `entity_type` of the current context (`album`, `playlist`, `track`, …).
    private var contextType: String?
    private var history = SoloistHistory()
    private var listQueue = SoloistListQueue()
    /// Details of the list's tracks (by URI), for the queue. Only the tracks
    /// `listQueue` keeps, so it is bounded the same way.
    private var listTracks: [String: Track] = [:]
    /// Soloist's own upcoming entries from the latest `queue_changed`.
    private var soloistUpcoming: [QueueEntry] = []
    private var queue = PlaybackQueue()
    /// The last session's track, shown paused until the user plays it or
    /// Soloist reports a track of its own (see `restore`).
    private var restored: PlaybackSnapshot?
    /// Where to seek once the restored track is playing.
    private var pendingSeek: (uri: String, positionMs: Int)?

    public init(configuration: SoloistConfiguration = SoloistConfiguration()) {
        (events, continuation) = AsyncStream.makeStream(
            of: PlaybackEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        process = SoloistProcess(configuration: configuration)
    }

    /// Launches (or attaches to) Soloist and connects to its WebSocket API.
    /// Soloist then sends `auth_state` and, if logged in, a full `playback_state`.
    @discardableResult
    public func start(apiKey: String) async throws(SoloistError) -> SoloistStartMode {
        let continuation = self.continuation
        let (mode, url) = try await process.start(apiKey: apiKey) { notice in
            switch notice {
            case .exited(.buildExpired): continuation.yield(.updateRequired)
            case .exited(let error): continuation.yield(.sourceStopped(error.localizedDescription))
            case .loginRejected: continuation.yield(.loginRejected)
            }
        }
        await connect(to: url)
        return mode
    }

    /// Connects to a Soloist that is already running (e.g. Aural's), without an
    /// API key and without stopping it later. For developer tools like the probe.
    @discardableResult
    public func attach() async throws(SoloistError) -> Int32 {
        let (pid, url) = try await process.attach()
        await connect(to: url)
        return pid
    }

    private func connect(to url: URL) async {
        let continuation = self.continuation
        let connection = SoloistConnection(url: url)
        self.connection = connection
        let stream = await connection.connect()

        // This task inherits the actor's isolation, so `handle` runs on the actor.
        // It is cancelled in `stop()`.
        listenTask = Task {
            do {
                for try await event in stream {
                    handle(event)
                }
            } catch {
                continuation.yield(.error("Lost connection to Soloist: \(error.localizedDescription)"))
            }
        }
    }

    public func stop() async {
        listenTask?.cancel()
        listenTask = nil
        await connection?.close()
        connection = nil
        await process.stop()
    }

    // MARK: - Events

    private func handle(_ event: SoloistEvent) {
        switch event {
        case .authState(let loggedIn, _):
            continuation.yield(.loginChanged(isLoggedIn: loggedIn))
        case .error(let message):
            continuation.yield(.error(message))
        case .unknown(let type):
            Log.soloist.debug("Ignoring unknown Soloist event \(type, privacy: .public)")
        case .playbackState(let snapshot):
            contextType = snapshot.context?.entityType
        case .contextChanged(let context):
            contextType = context?.entityType
        default:
            break
        }

        var newState = state.applying(event)
        if let restored {
            if newState.track == nil {
                // Soloist has nothing loaded: keep showing the restored track.
                newState = Self.state(showing: restored, on: newState)
            } else {
                self.restored = nil // Soloist plays something: that wins.
            }
        }
        let trackStarted = newState.track.map(\.id).flatMap { $0 != state.track?.id ? $0 : nil }
        if let uri = trackStarted {
            // Another track started before the restored one played: its
            // saved position no longer applies.
            if let seek = pendingSeek, seek.uri != uri { pendingSeek = nil }
            history.trackStarted(uri)
            switch listQueue.trackStarted(uri) {
            case .addToQueue(let next): Task { await sendLogged(.addToQueue(uri: next)) }
            case .skip: Task { await sendLogged(.skipNext) }
            case nil: break
            }
        }
        if newState != state {
            state = newState
            continuation.yield(.stateChanged(newState))
        }
        seekRestoredTrackIfReady()

        if case .queueChanged(let upcoming) = event {
            soloistUpcoming = QueueEntry.entries(soloist: upcoming)
            let requeue = history.tracksToRequeue(upcoming: upcoming, currentURI: state.track?.id)
            if !requeue.isEmpty { Task { await addToQueue(requeue) } }
            publishQueue()
        } else if trackStarted != nil {
            publishQueue()
        }
    }

    /// Sends the queue if it changed. While Aural plays a list, Soloist's
    /// queue holds only the list's next track, so the queue shows the rest
    /// of the list instead. Otherwise it is Soloist's own (playlist / album,
    /// autoplay), without tracks Aural is going to skip.
    private func publishQueue() {
        var newQueue = PlaybackQueue()
        if listQueue.isPlaying(state.track?.id) {
            newQueue.upNext = listQueue.upcoming.prefix(PlaybackQueue.limit).enumerated().compactMap { offset, uri in
                listTracks[uri].map { QueueEntry(id: "list-\(offset)-\(uri)", track: $0, source: .list) }
            }
            newQueue.canJump = true
        } else {
            newQueue.upNext = soloistUpcoming.filter { !listQueue.isStale($0.track.id) }
        }
        guard newQueue != queue else { return }
        queue = newQueue
        continuation.yield(.queueChanged(newQueue))
    }

    private func addToQueue(_ uris: [String]) async {
        for uri in uris { await sendLogged(.addToQueue(uri: uri)) }
    }

    /// For commands Aural sends by itself (not on a user action): failures
    /// are logged, not thrown.
    private func sendLogged(_ command: SoloistCommand) async {
        do {
            try await send(command)
        } catch {
            Log.soloist.error("\(command.name, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Commands (PlaybackSource)

    public func play(uri: String) async throws {
        listQueue.stop()
        listTracks = [:]
        publishQueue()
        try await send(.play(uri: uri))
    }

    /// Plays the chosen track and keeps the next track of the list queued
    /// (see `SoloistListQueue`).
    public func play(tracks: [Track], startingAt index: Int) async throws {
        guard let step = listQueue.start(tracks.map(\.id), at: index) else { return }
        let byURI = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        listTracks = Dictionary(listQueue.uris.compactMap { uri in byURI[uri].map { (uri, $0) } }, uniquingKeysWith: { first, _ in first })
        try await send(.play(uri: step.play))
        if let next = step.queue { try await send(.addToQueue(uri: next)) }
    }

    /// Jumps to an entry of the list Aural is playing.
    public func jump(toQueueEntry id: QueueEntry.ID) async throws {
        guard queue.canJump, let position = queue.upNext.firstIndex(where: { $0.id == id }),
              let step = listQueue.start(listQueue.uris, at: listQueue.index + 1 + position)
        else { return }
        try await control(.play(uri: step.play))
        if let next = step.queue { try await send(.addToQueue(uri: next)) }
    }

    public func resume() async throws {
        if restored != nil { return try await playRestored(skippingCurrent: false) }
        try await control(.play(uri: nil))
    }
    public func pause() async throws { try await control(.pause) }
    public func next() async throws {
        if restored != nil { return try await playRestored(skippingCurrent: true) }
        try await control(.skipNext)
    }
    /// Restarts the track after 5 s, otherwise goes to the track that played
    /// before (see `SoloistHistory`).
    public func previous() async throws {
        if restored != nil { return try await seekAndUpdate(to: 0) }
        let positionMs = state.position.current(durationMs: state.track?.durationMs)
        let inContext = contextType == "album" || contextType == "playlist"
        // Inside a list Aural is playing: the list's previous track.
        if !inContext, positionMs < SoloistHistory.restartThresholdMs,
           listQueue.isPlaying(state.track?.id), let step = listQueue.startPrevious() {
            try await control(.play(uri: step.play))
            if let next = step.queue { try await send(.addToQueue(uri: next)) }
            return
        }
        switch history.previous(currentURI: state.track?.id, positionMs: positionMs, contextType: contextType) {
        case .skipInContext:
            // Soloist's `skip_prev` restarts the track instead when it is
            // past its own threshold (~3 s), which would need a second press
            // between 3 and 5 s. At 0 it always goes to the previous track.
            try await control(.seek(positionMs: 0))
            try await control(.skipPrevious)
        case .restart: try await seekAndUpdate(to: 0)
        case .play(let uri):
            listQueue.stop()
            try await control(.play(uri: uri))
        }
    }
    public func seek(toMs positionMs: Int) async throws { try await seekAndUpdate(to: max(0, positionMs)) }

    /// Seeks, then moves the position anchor right away. Soloist does not
    /// always report a seek: restarting a track that started at 0 sends no
    /// `position_sync` (its last reported anchor was already 0), so the
    /// progress ring would keep running from the old position. A later
    /// report from Soloist replaces this estimate.
    private func seekAndUpdate(to positionMs: Int) async throws {
        if restored != nil {
            // Nothing is loaded in Soloist yet: remember the position for `resume`.
            restored?.positionMs = positionMs
        } else {
            try await control(.seek(positionMs: positionMs))
        }
        var newState = state
        newState.position = PlaybackPosition(positionMs: positionMs, timestamp: .now, speed: state.position.speed)
        if newState != state {
            state = newState
            continuation.yield(.stateChanged(newState))
        }
    }
    public func setVolume(_ volume: Int) async throws { try await send(.setVolume(min(100, max(0, volume)))) }
    public func setShuffle(_ enabled: Bool) async throws { try await control(.setShuffle(enabled)) }

    public func setRepeat(_ mode: RepeatMode) async throws {
        for command in SoloistCommand.commands(for: mode) {
            try await control(command)
        }
    }

    /// Soloist has no command to clear its queue, so Aural stops continuing
    /// its list and skips the queued songs when they start. A queued song
    /// may sound for a moment before it is skipped.
    public func clearQueue() async throws {
        let queued = soloistUpcoming.filter { $0.source == .queue }.map(\.track.id)
        listQueue.stop()
        listQueue.skipWhenStarted(queued)
        listTracks = [:]
        publishQueue()
    }

    /// Makes Soloist Spotify's active device (taking playback from the other
    /// device), then resumes there.
    public func playHere() async throws {
        if restored != nil { return try await playRestored(skippingCurrent: false) }
        try await send(.activate)
        try await send(.play(uri: nil))
    }

    /// Soloist accepts only track URIs here.
    public func addToQueue(uri: String) async throws { try await send(.addToQueue(uri: uri)) }

    /// Sends a playback control. If another device took over Spotify playback
    /// (e.g. the phone), Soloist ignores controls until it is active again, so
    /// Aural activates it first — the user pressed a button in Aural.
    private func control(_ command: SoloistCommand) async throws {
        if !state.isActiveDevice, state.track != nil {
            try await send(.activate)
        }
        try await send(command)
    }

    private func send(_ command: SoloistCommand) async throws {
        guard let connection else { throw SoloistError.notConnected }
        try await connection.send(command)
    }

    // MARK: - Last session (PlaybackSource)

    public func snapshot() -> PlaybackSnapshot? {
        if let restored { return restored } // not played since launch
        guard let track = state.track else { return nil }
        let upcoming: [Track] = if listQueue.isPlaying(track.id) {
            listQueue.upcoming.prefix(PlaybackQueue.limit).compactMap { listTracks[$0] }
        } else {
            // The playlist / album (Soloist reports at most 10) and queued
            // songs; autoplay picks new songs by itself anyway.
            soloistUpcoming.filter { $0.source != .autoplay && !listQueue.isStale($0.track.id) }.map(\.track)
        }
        return PlaybackSnapshot(
            track: track,
            positionMs: state.position.current(durationMs: track.durationMs),
            contextName: state.contextName,
            upcoming: upcoming
        )
    }

    public func restore(_ snapshot: PlaybackSnapshot) {
        guard state.track == nil else { return }
        restored = snapshot
        state = Self.state(showing: snapshot, on: state)
        continuation.yield(.stateChanged(state))
    }

    /// The restored track as a paused state. Only play and seek are offered:
    /// shuffle and repeat need a context Soloist has not loaded.
    private static func state(showing snapshot: PlaybackSnapshot, on base: PlaybackState) -> PlaybackState {
        var state = base
        state.status = .paused
        state.track = snapshot.track
        state.position = PlaybackPosition(positionMs: snapshot.positionMs, timestamp: .now, speed: 0)
        state.contextName = snapshot.contextName
        state.availableActions = [.play, .seek, .skipNext]
        return state
    }

    /// Seeks the restored track to its saved position once Soloist reports
    /// it as playing. Sent any earlier (e.g. on `track_changed`, while the
    /// track is still loading), Soloist ignores the seek and the track
    /// starts at 0:00 (seen in testing). One retry if it still did not move.
    private func seekRestoredTrackIfReady() {
        guard let seek = pendingSeek, state.track?.id == seek.uri, state.status == .playing else { return }
        pendingSeek = nil
        Task {
            try? await seekAndUpdate(to: seek.positionMs)
            try? await Task.sleep(for: .seconds(1.5))
            // The local estimate is replaced by Soloist's next report: if
            // that says it is still near the start, the seek was dropped.
            guard state.track?.id == seek.uri,
                  state.position.current(durationMs: state.track?.durationMs) < seek.positionMs - 3_000
            else { return }
            Log.soloist.notice("Restored position was not applied; seeking again")
            try? await seekAndUpdate(to: seek.positionMs)
        }
    }

    /// Plays the restored track and what followed it as a list (Soloist's
    /// `play` cannot start a playlist or album at a given track), then seeks
    /// to the saved position once the track has started.
    private func playRestored(skippingCurrent: Bool) async throws {
        guard let snapshot = restored else { return }
        let tracks = [snapshot.track] + snapshot.upcoming
        let index = skippingCurrent ? 1 : 0
        guard tracks.indices.contains(index) else { return }
        restored = nil
        // Forget the shown track without telling the UI, so Soloist's report
        // counts as "track started" (for the list) but the player does not
        // flash empty in between.
        state.track = nil
        if !skippingCurrent, snapshot.positionMs > 0 {
            pendingSeek = (snapshot.track.id, snapshot.positionMs)
        }
        do {
            try await play(tracks: tracks, startingAt: index)
        } catch {
            // Nothing started: keep showing the restored track, so play can be tried again.
            pendingSeek = nil
            restored = snapshot
            state.track = snapshot.track
            throw error
        }
    }
}
