import AuralCore
import CoreGraphics
import Foundation
import Observation
import os

/// App-wide state: whether setup is needed, the current playback state, and
/// the connection to Soloist. Views read it; all changes happen on the main actor.
///
/// `@Observable` makes SwiftUI re-render views that read a property when it
/// changes (similar to a reactive store).
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        /// Checking the install / starting Soloist.
        case starting
        case setup
        case player
    }

    private(set) var phase: Phase = .starting
    private(set) var playback = PlaybackState()
    private(set) var artwork: CGImage?
    private(set) var isLoggedIn = false
    /// Shown in the player when something went wrong (e.g. Soloist stopped).
    private(set) var problem: String?

    let setup: SetupModel

    @ObservationIgnored private let configuration = SoloistConfiguration()
    @ObservationIgnored private var soloist: SoloistSource?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var nowPlaying: NowPlayingController?

    private let log = Logger(subsystem: "app.aural", category: "app")

    /// Cover size in the player (110 pt) at 2× plus margin for the Now Playing widget.
    private static let artworkPixelSize = 300

    init() {
        setup = SetupModel(installer: SoloistInstaller(executableURL: configuration.executableURL))
        setup.delegate = self
        nowPlaying = NowPlayingController(
            togglePlayPause: { [weak self] in self?.togglePlayPause() },
            play: { [weak self] in self?.send { try await $0.resume() } },
            pause: { [weak self] in self?.send { try await $0.pause() } },
            next: { [weak self] in self?.next() },
            previous: { [weak self] in self?.previous() },
            seek: { [weak self] seconds in self?.seek(toMs: Int(seconds * 1000)) }
        )
    }

    // MARK: - Lifecycle

    /// Decides between setup and player. With a valid install and a stored key,
    /// Soloist is started and the saved pairing session restores the login.
    func launch() async {
        let installed = await setup.refreshInstalledVersion()
        let storedKey = try? Keychain.readPassword(service: SoloistConfiguration.apiKeyKeychainService)
        guard installed, let storedKey else {
            phase = .setup
            return
        }

        do {
            try await startSoloist(apiKey: storedKey)
        } catch {
            setup.showKeyStep(error: error.localizedDescription)
            phase = .setup
            return
        }

        // The restored session logs in within ~0.3 s; allow some margin before
        // assuming the pairing is gone and asking to pair again.
        try? await Task.sleep(for: .seconds(5))
        if phase == .starting {
            setup.showPairStep(pendingKey: nil)
            phase = .setup
        }
    }

    func shutdown() async {
        nowPlaying?.clear()
        await stopSoloist()
    }

    // MARK: - Soloist connection

    private func startSoloist(apiKey: String) async throws {
        await stopSoloist()
        let source = SoloistSource(configuration: configuration)
        try await source.start(apiKey: apiKey)
        soloist = source
        problem = nil
        // Single consumer of the event stream for the whole app.
        eventsTask = Task { [weak self] in
            for await event in source.events {
                self?.handle(event)
            }
        }
    }

    private func stopSoloist() async {
        eventsTask?.cancel()
        eventsTask = nil
        if let soloist {
            self.soloist = nil
            await soloist.stop()
        }
        isLoggedIn = false
    }

    private func handle(_ event: PlaybackEvent) {
        switch event {
        case .stateChanged(let state):
            let trackChanged = state.track?.id != playback.track?.id
            playback = state
            if trackChanged { loadArtwork(for: state.track) }
            nowPlaying?.update(state, artwork: artwork)
        case .loginChanged(let loggedIn):
            isLoggedIn = loggedIn
            if loggedIn {
                switch phase {
                case .starting: phase = .player
                case .setup: setup.loginSucceeded()
                case .player: break
                }
            }
        case .loginRejected:
            setup.loginRejected()
            if phase != .setup { phase = .setup }
        case .sourceStopped(let message):
            problem = message
            log.error("Soloist stopped: \(message, privacy: .public)")
        case .error(let message):
            log.error("Soloist error: \(message, privacy: .public)")
        }
    }

    private func loadArtwork(for track: Track?) {
        artworkTask?.cancel()
        artwork = nil // release the previous image right away
        guard let url = track?.artworkURL else { return }
        artworkTask = Task { [weak self] in
            guard let image = try? await ArtworkLoader.load(url, maxPixelSize: Self.artworkPixelSize),
                  !Task.isCancelled, let self
            else { return }
            artwork = image
            nowPlaying?.update(playback, artwork: image)
        }
    }

    // MARK: - Commands

    func togglePlayPause() {
        if playback.status == .playing {
            send { try await $0.pause() }
        } else {
            send { try await $0.resume() }
        }
    }

    func next() { send { try await $0.next() } }
    func previous() { send { try await $0.previous() } }
    func seek(toMs positionMs: Int) { send { try await $0.seek(toMs: positionMs) } }

    /// Sends a command without blocking the UI. Results arrive as events.
    private func send(_ command: @escaping @Sendable (SoloistSource) async throws -> Void) {
        guard let soloist else { return }
        Task {
            do {
                try await command(soloist)
            } catch {
                log.error("Command failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

// MARK: - Setup actions

extension AppModel: SetupModel.Delegate {
    func setupStartSoloist(apiKey: String) async throws {
        try await startSoloist(apiKey: apiKey)
    }

    func setupStopSoloist() async {
        await stopSoloist()
    }

    func setupFinished() {
        phase = .player
    }

    func setupIsLoggedIn() -> Bool {
        isLoggedIn
    }
}
