import Foundation

/// One WebSocket connection to Soloist: sends commands, streams decoded events.
actor SoloistConnection {
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    private var receiveTask: Task<Void, Never>?

    init(url: URL) {
        // Ephemeral: no cookies or disk cache for a local control socket.
        session = URLSession(configuration: .ephemeral)
        task = session.webSocketTask(with: url)
    }

    /// Opens the connection and returns its events. Call once.
    /// The stream ends with an error when the connection drops.
    func connect() -> AsyncThrowingStream<SoloistEvent, any Error> {
        // Bounded buffer: if the consumer falls behind, the oldest events are
        // dropped. A later `playback_state` snapshot corrects any gap.
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: SoloistEvent.self,
            bufferingPolicy: .bufferingNewest(64)
        )
        task.resume()

        let task = self.task
        receiveTask = Task {
            do {
                while !Task.isCancelled {
                    let data: Data
                    switch try await task.receive() {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: continue
                    }
                    do {
                        continuation.yield(try SoloistEvent.decode(from: data))
                    } catch {
                        // One malformed or unexpected message must not end the session.
                        Log.soloist.error("Could not decode Soloist message: \(error, privacy: .public)")
                    }
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
        return stream
    }

    func send(_ command: SoloistCommand) async throws {
        let data = try JSONEncoder().encode(command)
        try await task.send(.string(String(decoding: data, as: UTF8.self)))
    }

    func close() {
        receiveTask?.cancel()
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}
