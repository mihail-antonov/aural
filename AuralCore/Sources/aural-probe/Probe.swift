import AuralCore
import Foundation

/// Command-line driver for AuralCore's Soloist source (Stage 1, before the app).
///
///     aural-probe [play <uri>]                                 attach to Aural's running Soloist
///     aural-probe --launch [--soloist PATH] [--name NAME] [play <uri>]
///     aural-probe [--soloist PATH] install
///     aural-probe webapi-check --client-id ID
///
/// By default it connects to the Soloist that Aural is running: no API key is
/// needed (so no Keychain prompt) and Soloist keeps running after Ctrl-C.
/// With `--launch` it starts its own Soloist, reading the key from the Keychain
/// (macOS asks for access, since the entry belongs to the Aural app).
/// Printing to stdout is this tool's purpose, not debug output.
@main
struct Probe {
    static func main() async {
        // Flush each line immediately, also when stdout is a file or pipe.
        setvbuf(stdout, nil, _IOLBF, 0)

        let options: Options
        do {
            options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
        } catch {
            fail(error.localizedDescription + "\n\n" + Options.usage)
        }

        if let clientID = options.webAPICheckClientID {
            guard !clientID.isEmpty else { fail("webapi-check needs --client-id ID") }
            await WebAPICheck.run(clientID: clientID, say: say)
            return
        }

        if options.install {
            await install(to: options.soloistPath ?? SoloistConfiguration.defaultExecutableURL)
            return
        }

        let configuration = SoloistConfiguration(executableURL: options.soloistPath, deviceName: options.deviceName)
        let source = SoloistSource(configuration: configuration)
        let shutdown = handleInterrupts(source: source)

        do {
            if options.launch {
                let apiKey: String
                do {
                    apiKey = try Keychain.readPassword(service: SoloistConfiguration.apiKeyKeychainService)
                } catch {
                    fail("Could not read the Soloist API key from the Keychain (\(error)).")
                }
                switch try await source.start(apiKey: apiKey) {
                case .launched: say("Launched Soloist: \(configuration.executableURL.path)")
                case .attached(let pid): say("Took over running Soloist (pid \(pid))")
                }
            } else {
                let pid = try await source.attach()
                say("Attached to Aural's Soloist (pid \(pid)); it keeps running after Ctrl-C")
            }
        } catch {
            fail(error.localizedDescription + (options.launch ? "" : " Open Aural first, or use --launch."))
        }
        say("Connected. Press Ctrl-C to stop.")

        var pendingURI = options.uri
        for await event in source.events {
            switch event {
            case .loginChanged(let isLoggedIn):
                say(isLoggedIn ? "login    logged in" : "login    not logged in — open Spotify and choose \"\(options.deviceName)\"")
                if isLoggedIn, let uri = pendingURI {
                    pendingURI = nil
                    say("command  play \(uri)")
                    do { try await source.play(uri: uri) } catch { say("error    \(error.localizedDescription)") }
                }
            case .stateChanged(let state):
                say("state    " + describe(state))
            case .queueChanged(let queue):
                // Shows whether Soloist's queue entries carry titles (needed by the Queue page).
                let sources = queue.upNext.map { "\($0.source)" }.joined(separator: ",")
                say("queue    \(queue.upNext.count) up next [\(sources)]; first: \(queue.upNext.first.map { "\($0.track.title) (\($0.track.durationMs) ms)" } ?? "-")")
            case .loginRejected:
                say("login    rejected — the API key is invalid")
            case .updateRequired:
                say("error    this Soloist build has expired — update it")
            case .sourceStopped(let message), .error(let message):
                say("error    \(message)")
            }
        }
        _ = shutdown
    }

    private static func install(to executable: URL) async {
        say("Downloading Soloist from \(SoloistInstaller.officialDownloadURL.absoluteString)")
        do {
            let version = try await SoloistInstaller(executableURL: executable).install()
            say("Installed Soloist \(version.version) at \(executable.path); expires \(version.expiryDate.formatted(date: .abbreviated, time: .omitted))")
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: - Output

    private static func describe(_ state: PlaybackState) -> String {
        let track = state.track.map { "\"\($0.title)\" — \($0.artists.joined(separator: ", "))" } ?? "(no track)"
        let duration = state.track?.durationMs ?? 0
        let position = state.position.current(durationMs: duration)
        let actions = state.availableActions.map(\.rawValue).sorted().joined(separator: " ")
        return "\(state.status.rawValue)  \(track)  \(time(position))/\(time(duration))"
            + "  vol \(state.volume)  shuffle \(state.shuffle ? "on" : "off")  repeat \(state.repeatMode.rawValue)"
            + "  [\(actions)]"
    }

    private static func time(_ ms: Int) -> String {
        let seconds = ms / 1000
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    private static func say(_ line: String) {
        let stamp = Date.now.formatted(date: .omitted, time: .standard)
        print("\(stamp)  \(line)")
    }

    private static func fail(_ message: String) -> Never {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        exit(1)
    }

    // MARK: - Ctrl-C

    /// Stops Soloist cleanly on Ctrl-C / SIGTERM instead of leaving it running.
    /// Returns the signal sources, which must stay alive for the handlers to fire.
    private static func handleInterrupts(source: SoloistSource) -> [any DispatchSourceSignal] {
        [SIGINT, SIGTERM].map { signalNumber in
            signal(signalNumber, SIG_IGN) // let the DispatchSource handle it instead
            let signalSource = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            signalSource.setEventHandler {
                Task {
                    say("Stopping…")
                    await source.stop()
                    exit(0)
                }
            }
            signalSource.resume()
            return signalSource
        }
    }
}

// MARK: - Arguments

private struct Options {
    static let usage = "usage: aural-probe [--launch] [--soloist PATH] [--name NAME] [play <uri> | install]\n       aural-probe webapi-check --client-id ID"

    var soloistPath: URL?
    var deviceName = "Aural"
    var uri: String?
    var install = false
    var launch = false
    var webAPICheckClientID: String?

    struct ArgumentError: LocalizedError {
        let errorDescription: String?
    }

    init(arguments: [String]) throws {
        var remaining = arguments[...] // an ArraySlice we can pop from
        while let argument = remaining.popFirst() {
            switch argument {
            case "--soloist":
                guard let path = remaining.popFirst() else { throw ArgumentError(errorDescription: "--soloist needs a path") }
                soloistPath = URL(filePath: (path as NSString).expandingTildeInPath)
            case "--name":
                guard let name = remaining.popFirst() else { throw ArgumentError(errorDescription: "--name needs a value") }
                deviceName = name
            case "play":
                guard let uri = remaining.popFirst() else { throw ArgumentError(errorDescription: "play needs a URI") }
                guard uri.hasPrefix("spotify:") else { throw ArgumentError(errorDescription: "not a Spotify URI: \(uri)") }
                self.uri = uri
            case "webapi-check":
                webAPICheckClientID = webAPICheckClientID ?? ""
            case "--client-id":
                guard let id = remaining.popFirst() else { throw ArgumentError(errorDescription: "--client-id needs a value") }
                webAPICheckClientID = id
            case "--launch":
                launch = true
            case "install":
                install = true
            case "-h", "--help":
                throw ArgumentError(errorDescription: "Plays a Spotify URI through Soloist and prints events.")
            default:
                throw ArgumentError(errorDescription: "unknown argument: \(argument)")
            }
        }
    }
}
