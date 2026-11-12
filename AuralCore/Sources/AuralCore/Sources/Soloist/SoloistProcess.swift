import Darwin
import Foundation
import os

/// Starts and stops the Soloist daemon, or attaches to one that is already
/// running with the same data directory.
///
/// An `actor` serialises access to its state (like a single-threaded object):
/// callers `await` its methods, so the `Process` is never touched from two
/// threads at once.
actor SoloistProcess {
    private let configuration: SoloistConfiguration
    /// Set when Aural launched Soloist itself.
    private var process: Process?
    /// Set when Aural attached to a Soloist already running in its data
    /// directory (e.g. left over after Aural crashed).
    private var attachedPID: pid_t?
    /// Shared with `Process.terminationHandler`, which runs on a background
    /// thread outside the actor, so it needs its own lock.
    private let exitState = OSAllocatedUnfairLock(initialState: ExitState())

    private struct ExitState {
        var exitError: SoloistError?
        var isStopping = false
    }

    init(configuration: SoloistConfiguration) {
        self.configuration = configuration
    }

    /// Things only visible in Soloist's process output, not over WebSocket.
    enum Notice: Sendable, Equatable {
        /// Soloist ended on its own (not because `stop()` was called).
        case exited(SoloistError)
        /// Spotify refused a pairing attempt: the API key is invalid.
        case loginRejected
    }

    /// Makes sure Soloist is running and returns how it was started and its WebSocket URL.
    /// A Soloist already running in Aural's data directory (e.g. left over after
    /// a crash) is taken over: `stop()` stops it too.
    /// - Parameter onNotice: called from a background thread for events of a
    ///   Soloist that Aural launched (an attached instance's output is not visible).
    func start(
        apiKey: String,
        onNotice: @escaping @Sendable (Notice) -> Void
    ) async throws(SoloistError) -> (SoloistStartMode, URL) {
        if let (pid, url) = try runningInstance() {
            attachedPID = pid
            return (.attached(pid: pid), url)
        }
        let url = try await launch(apiKey: apiKey, onNotice: onNotice)
        return (.launched, url)
    }

    /// Connects to an already running Soloist without taking it over (no API key
    /// needed). `stop()` leaves it running. Used by developer tools.
    func attach() throws(SoloistError) -> (pid: pid_t, url: URL) {
        guard let instance = try runningInstance() else { throw .notRunning }
        return instance
    }

    private func runningInstance() throws(SoloistError) -> (pid: pid_t, url: URL)? {
        guard let pid = runningInstancePID() else { return nil }
        Log.soloist.info("Attaching to running Soloist (pid \(pid))")
        guard let url = webSocketURL(writtenAfter: nil) else { throw .runningWithoutWebSocket }
        return (pid, url)
    }

    /// Stops Soloist if Aural launched it or took it over in `start`.
    func stop() async {
        if let pid = attachedPID {
            attachedPID = nil
            await Self.terminate(pid: pid)
        }
        guard let process else { return }
        self.process = nil
        exitState.withLock { $0.isStopping = true }
        guard process.isRunning else { return }

        // SIGTERM lets Soloist shut down cleanly (it removes ws.port / ws.addr).
        process.terminate()
        for _ in 0..<50 where process.isRunning {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if process.isRunning {
            Log.soloist.error("Soloist did not stop in 5 s, killing it")
            kill(process.processIdentifier, SIGKILL)
        }
        Log.soloist.info("Soloist stopped")
    }

    /// SIGTERM, wait up to 5 s, then SIGKILL — for a process we did not launch.
    private static func terminate(pid: pid_t) async {
        guard kill(pid, SIGTERM) == 0 else { return }
        for _ in 0..<50 where kill(pid, 0) == 0 {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        Log.soloist.info("Stopped attached Soloist (pid \(pid))")
    }

    // MARK: - Launch

    private func launch(
        apiKey: String,
        onNotice: @escaping @Sendable (Notice) -> Void
    ) async throws(SoloistError) -> URL {
        let executable = configuration.executableURL
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw .executableNotFound(path: executable.path)
        }

        let process = Process()
        process.executableURL = executable
        // The API key can only be passed as an argument (Soloist has no env var
        // or config file for it). It is never logged.
        process.arguments = [
            "--device-name", configuration.deviceName,
            "--api-key", apiKey,
            "--data-dir", configuration.dataDirectory.path,
            "--ws", "127.0.0.1:0", // loopback only: the API has no authentication
            "--cache-size", String(configuration.cacheSizeMB),
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = Self.forwardingPipe(onNotice: onNotice)
        process.standardError = process.standardOutput

        exitState.withLock { $0 = ExitState() }
        let exitState = self.exitState
        process.terminationHandler = { finished in
            let error = Self.error(for: finished)
            let wasStopping = exitState.withLock { state in
                state.exitError = error
                return state.isStopping
            }
            if !wasStopping {
                Log.soloist.error("Soloist ended unexpectedly: \(error.localizedDescription, privacy: .public)")
                onNotice(.exited(error))
            }
        }

        // ws.port may be left over from an earlier crash, so only a file
        // written after this launch counts. 1 s of slack for file-system timestamps.
        let launchDate = Date().addingTimeInterval(-1)
        do {
            try process.run()
        } catch {
            throw .launchFailed(error.localizedDescription)
        }
        self.process = process
        Log.soloist.info("Launched Soloist (pid \(process.processIdentifier))")

        let deadline = ContinuousClock.now + configuration.startTimeout
        while ContinuousClock.now < deadline {
            if let exitError = exitState.withLock({ $0.exitError }) {
                self.process = nil
                throw exitError
            }
            if let url = webSocketURL(writtenAfter: launchDate) {
                return url
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        await stop()
        throw .startTimeout
    }

    /// `terminationStatus` is an exit code for a normal exit, but the signal
    /// number when the process was killed, so check `terminationReason` first.
    private static func error(for finished: Process) -> SoloistError {
        let status = finished.terminationStatus
        switch finished.terminationReason {
        case .uncaughtSignal: return .killed(signal: status)
        case .exit: return status == 10 ? .buildExpired : .exited(code: status)
        @unknown default: return .exited(code: status)
        }
    }

    /// Soloist's output line when Spotify rejects the API key during pairing,
    /// e.g. `2026-11-12 13:36:58.812: login failed: make sure --api-key is valid`.
    /// Soloist sends no WebSocket event for this, so this line is the only signal.
    /// Log text is not a stable API: keep the pattern here, in one place.
    static func isLoginRejection(_ line: some StringProtocol) -> Bool {
        line.contains(": login failed")
    }

    /// A pipe whose output is forwarded line by line to the unified log.
    /// The pipe must be drained: if nobody reads it, its buffer fills up and
    /// Soloist blocks on its next log line.
    private static func forwardingPipe(onNotice: @escaping @Sendable (Notice) -> Void) -> Pipe {
        let pipe = Pipe()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil // end of file: Soloist exited
                return
            }
            for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) {
                // `.private`: lines can contain the account's user name.
                Log.soloistOutput.debug("\(line, privacy: .private)")
                if isLoginRejection(line) { onNotice(.loginRejected) }
            }
        }
        return pipe
    }

    // MARK: - Discovery files in the data directory

    /// PID of a Soloist process that owns our data directory, if one is running.
    private func runningInstancePID() -> pid_t? {
        let pidFile = configuration.dataDirectory.appending(path: "soloist.pid")
        guard let text = try? String(contentsOf: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)),
              pid > 0,
              kill(pid, 0) == 0 // signal 0 = "does this process exist?", sends nothing
        else { return nil }

        // The PID file may be stale and the number reused by another program.
        guard Self.executableName(of: pid) == "soloist" else { return nil }
        return pid
    }

    private static func executableName(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4096) // PROC_PIDPATHINFO_MAXSIZE
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path).lastPathComponent
    }

    /// Reads `ws.addr` and `ws.port`, which Soloist writes once its WebSocket
    /// server is listening.
    private func webSocketURL(writtenAfter date: Date?) -> URL? {
        let portFile = configuration.dataDirectory.appending(path: "ws.port")
        let addressFile = configuration.dataDirectory.appending(path: "ws.addr")

        if let date {
            let attributes = try? FileManager.default.attributesOfItem(atPath: portFile.path)
            guard let modified = attributes?[.modificationDate] as? Date, modified >= date else { return nil }
        }
        guard let portText = try? String(contentsOf: portFile, encoding: .utf8),
              let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65535).contains(port)
        else { return nil }

        let address = (try? String(contentsOf: addressFile, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Only ever connect to loopback, whatever the file says.
        guard address == nil || address == "127.0.0.1" else {
            Log.soloist.error("Soloist WebSocket is not bound to loopback; refusing to connect")
            return nil
        }
        return URL(string: "ws://127.0.0.1:\(port)")
    }
}
