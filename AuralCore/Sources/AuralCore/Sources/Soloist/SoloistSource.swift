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
        if let uri = newState.track?.id, uri != state.track?.id { history.trackStarted(uri) }
        if newState != state {
            state = newState
            continuation.yield(.stateChanged(newState))
        }

        if case .queueChanged(let upcoming) = event {
            let requeue = history.tracksToRequeue(upcoming: upcoming, currentURI: state.track?.id)
            if !requeue.isEmpty { Task { await addToQueue(requeue) } }
        }
    }

    private func addToQueue(_ uris: [String]) async {
        do {
            for uri in uris { try await send(.addToQueue(uri: uri)) }
        } catch {
            Log.soloist.error("Re-queueing after previous failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Commands (PlaybackSource)

    public func play(uri: String) async throws { try await send(.play(uri: uri)) }
    public func resume() async throws { try await send(.play(uri: nil)) }
    public func pause() async throws { try await send(.pause) }
    public func next() async throws { try await send(.skipNext) }
    /// Like Spotify: restarts the track after 3 s, otherwise goes to the track
    /// that played before (see `SoloistHistory`).
    public func previous() async throws {
        let positionMs = state.position.current(durationMs: state.track?.durationMs)
        switch history.previous(currentURI: state.track?.id, positionMs: positionMs, contextType: contextType) {
        case .skipInContext: try await send(.skipPrevious)
        case .restart: try await send(.seek(positionMs: 0))
        case .play(let uri): try await send(.play(uri: uri))
        }
    }
    public func seek(toMs positionMs: Int) async throws { try await send(.seek(positionMs: max(0, positionMs))) }
    public func setVolume(_ volume: Int) async throws { try await send(.setVolume(min(100, max(0, volume)))) }
    public func setShuffle(_ enabled: Bool) async throws { try await send(.setShuffle(enabled)) }

    public func setRepeat(_ mode: RepeatMode) async throws {
        for command in SoloistCommand.commands(for: mode) {
            try await send(command)
        }
    }

    /// Soloist accepts only track URIs here.
    public func addToQueue(uri: String) async throws { try await send(.addToQueue(uri: uri)) }

    private func send(_ command: SoloistCommand) async throws {
        guard let connection else { throw SoloistError.notConnected }
        try await connection.send(command)
    }
}
