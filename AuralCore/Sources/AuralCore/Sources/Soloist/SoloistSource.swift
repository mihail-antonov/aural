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
        let (mode, url) = try await process.start(apiKey: apiKey) { error in
            continuation.yield(.error(error.localizedDescription))
        }

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
        return mode
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
        default:
            break
        }

        let newState = state.applying(event)
        if newState != state {
            state = newState
            continuation.yield(.stateChanged(newState))
        }
    }

    // MARK: - Commands (PlaybackSource)

    public func play(uri: String) async throws { try await send(.play(uri: uri)) }
    public func resume() async throws { try await send(.play(uri: nil)) }
    public func pause() async throws { try await send(.pause) }
    public func next() async throws { try await send(.skipNext) }
    public func previous() async throws { try await send(.skipPrevious) }
    public func seek(toMs positionMs: Int) async throws { try await send(.seek(positionMs: max(0, positionMs))) }
    public func setVolume(_ volume: Int) async throws { try await send(.setVolume(min(100, max(0, volume)))) }
    public func setShuffle(_ enabled: Bool) async throws { try await send(.setShuffle(enabled)) }

    public func setRepeat(_ mode: RepeatMode) async throws {
        for command in SoloistCommand.commands(for: mode) {
            try await send(command)
        }
    }

    private func send(_ command: SoloistCommand) async throws {
        guard let connection else { throw SoloistError.notConnected }
        try await connection.send(command)
    }
}
