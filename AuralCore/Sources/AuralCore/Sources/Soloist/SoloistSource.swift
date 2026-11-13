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

        let newState = state.applying(event)
        let trackStarted = newState.track.map(\.id).flatMap { $0 != state.track?.id ? $0 : nil }
        if let uri = trackStarted {
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

    public func resume() async throws { try await control(.play(uri: nil)) }
    public func pause() async throws { try await control(.pause) }
    public func next() async throws { try await control(.skipNext) }
    /// Like Spotify: restarts the track after 3 s, otherwise goes to the track
    /// that played before (see `SoloistHistory`).
    public func previous() async throws {
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
        case .skipInContext: try await control(.skipPrevious)
        case .restart: try await control(.seek(positionMs: 0))
        case .play(let uri):
            listQueue.stop()
            try await control(.play(uri: uri))
        }
    }
    public func seek(toMs positionMs: Int) async throws { try await control(.seek(positionMs: max(0, positionMs))) }
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
}
