import Foundation
import Network

/// A tiny one-shot HTTP server on 127.0.0.1 that receives the OAuth redirect
/// (`/callback?code=…&state=…`) after the user signs in in their browser.
///
/// Network.framework reports everything through callbacks on `queue`. All
/// mutable state is only touched on that serial queue, which is why the class
/// can be marked `@unchecked Sendable` (the compiler cannot verify this itself).
final class LoopbackServer: @unchecked Sendable {
    struct Callback {
        let query: [String: String]
    }

    private let port: UInt16
    private let path: String
    private let queue = DispatchQueue(label: "app.aural.loopback-server")
    private var listener: NWListener?
    private var continuation: CheckedContinuation<Callback, any Error>?

    init(port: UInt16, path: String) {
        self.port = port
        self.path = path
    }

    /// Starts listening and waits for one request to `path`. Other requests
    /// (e.g. the browser asking for `/favicon.ico`) get a 404 and are ignored.
    func waitForCallback(timeout: Duration) async throws -> Callback {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { self.start(continuation: continuation, timeout: timeout) }
            }
        } onCancel: {
            queue.async { self.finish(.failure(SpotifyAuthError.loginCancelled)) }
        }
    }

    // MARK: - On `queue`

    private func start(continuation: CheckedContinuation<Callback, any Error>, timeout: Duration) {
        self.continuation = continuation
        do {
            let parameters = NWParameters.tcp
            // Bind to the loopback interface only: nothing outside this Mac can connect.
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed = state {
                    self?.finish(.failure(SpotifyAuthError.callbackPortUnavailable(self?.port ?? 0)))
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            finish(.failure(SpotifyAuthError.callbackPortUnavailable(port)))
            return
        }
        queue.asyncAfter(deadline: .now() + timeout.timeInterval) { [weak self] in
            self?.finish(.failure(SpotifyAuthError.timedOut))
        }
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = String(decoding: data ?? Data(), as: UTF8.self)
            // Request line: "GET /callback?code=…&state=… HTTP/1.1"
            let target = request.split(separator: " ", maxSplits: 2).dropFirst().first.map(String.init) ?? ""
            let components = URLComponents(string: "http://127.0.0.1\(target)")

            guard components?.path == path else {
                respond(connection, status: "404 Not Found", body: "Not found")
                return
            }
            var query: [String: String] = [:]
            for item in components?.queryItems ?? [] { query[item.name] = item.value ?? "" }

            let success = query["code"] != nil
            respond(connection, status: "200 OK", body: success
                ? "Aural is connected to your Spotify library. You can close this tab."
                : "Aural was not connected. You can close this tab and try again in Aural.")
            finish(.success(Callback(query: query)))
        }
    }

    private func respond(_ connection: NWConnection, status: String, body: String) {
        let html = "<!doctype html><meta charset=utf-8><title>Aural</title>"
            + "<body style=\"font:16px -apple-system;margin:4em;text-align:center\">\(body)</body>"
        let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
            + "Content-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Resumes the waiting caller exactly once and stops listening.
    private func finish(_ result: Result<Callback, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        listener?.cancel()
        listener = nil
        continuation.resume(with: result)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
