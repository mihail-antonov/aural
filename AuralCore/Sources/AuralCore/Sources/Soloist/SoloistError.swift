import Foundation

public enum SoloistError: Error, Equatable {
    case executableNotFound(path: String)
    case launchFailed(String)
    /// Soloist exited with code 10: the build is older than 90 days.
    case buildExpired
    /// Soloist exited unexpectedly with this code.
    case exited(code: Int32)
    /// Soloist was terminated by a signal (crash or killed).
    case killed(signal: Int32)
    /// Soloist started but its WebSocket server did not appear in time.
    case startTimeout
    /// Another Soloist owns the data directory but was started without `--ws`.
    case runningWithoutWebSocket
    /// `attach()` found no running Soloist.
    case notRunning
    case notConnected
}

extension SoloistError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let path): "Soloist was not found at \(path)."
        case .launchFailed(let reason): "Soloist could not be started: \(reason)"
        case .buildExpired: "This Soloist build has expired. Install the latest version."
        case .exited(let code): "Soloist stopped unexpectedly (exit code \(code))."
        case .killed(let signal): "Soloist was terminated (signal \(signal))."
        case .startTimeout: "Soloist did not start its control interface in time."
        case .runningWithoutWebSocket: "Soloist is already running without its control interface. Quit it and try again."
        case .notRunning: "Soloist is not running."
        case .notConnected: "Not connected to Soloist."
        }
    }
}
