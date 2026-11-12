import Foundation

/// Runs a short-lived command and collects its output (e.g. `tar`, `soloist --version`).
/// Not for long-running processes: output is collected in memory.
enum ProcessRunner {
    struct Result: Sendable {
        let status: Int32
        let output: String
    }

    static func run(_ executable: URL, arguments: [String]) async throws -> Result {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        // `withCheckedThrowingContinuation` turns the callback-based
        // `terminationHandler` into something we can `await`. The handler is
        // set before `run()`, so a very fast exit cannot be missed.
        return try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { finished in
                let data = (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
                continuation.resume(returning: Result(
                    status: finished.terminationStatus,
                    output: String(decoding: data, as: UTF8.self)
                ))
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }
}
