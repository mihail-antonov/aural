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
    /// Average color of the current cover, for the tinted background. Kept
    /// from the previous track until the new cover has loaded.
    private(set) var coverColor: ArtworkColor?
    private(set) var isLoggedIn = false
    /// Shown in the player when something went wrong (e.g. Soloist stopped).
    private(set) var problem: String?

    /// Spotify Web API access (library, search, likes). Nil until connected.
    private(set) var library: LibraryService?
    /// Whether the current track is in Liked Songs; nil while unknown.
    private(set) var isCurrentTrackLiked: Bool?
    /// Increases after every like/unlike so the Liked Songs list can reload.
    private(set) var likedSongsVersion = 0

    /// Pages of the main window. The player's list button opens the library,
    /// its search button the search; their back chevron (or Esc) returns to
    /// the player.
    enum Page {
        case player, library, search
    }

    var page: Page = .player

    /// Installed Soloist version, for the `…` menu.
    var soloistVersion: SoloistVersion? { setup.installedVersion }

    let setup: SetupModel

    @ObservationIgnored private let configuration = SoloistConfiguration()
    @ObservationIgnored private var soloist: SoloistSource?
    @ObservationIgnored private var eventsTask: Task<Void, Never>?
    @ObservationIgnored private var artworkTask: Task<Void, Never>?
    @ObservationIgnored private var nowPlaying: NowPlayingController?
    @ObservationIgnored private var likeTask: Task<Void, Never>?

    /// How many following tracks are queued when a track is played from a list
    /// (Soloist's `play` cannot start a playlist or album at a given track).
    private static let queuedFollowingTracks = 20

    private let log = Logger(subsystem: "app.aural", category: "app")

    /// Cover size in the player (225 pt) at 2×. One decoded image of this
    /// size is ~0.8 MB; only the current cover is kept in memory.
    private static let artworkPixelSize = 450

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
        if let credentials = WebAPICredentials.load() { connectLibrary(credentials) }
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
            if trackChanged {
                loadArtwork(for: state.track)
                refreshLiked(for: state.track)
            }
            nowPlaying?.update(state, artwork: artwork)
        case .loginChanged(let loggedIn):
            isLoggedIn = loggedIn
            if loggedIn {
                switch phase {
                case .starting: phase = needsLibrarySetup ? showLibrarySetup() : .player
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
            coverColor = ArtworkLoader.averageColor(of: image)
            nowPlaying?.update(playback, artwork: image)
        }
    }

    // MARK: - Library

    private var needsLibrarySetup: Bool {
        library == nil && !UserDefaults.standard.bool(forKey: SetupModel.librarySkippedKey)
    }

    private func showLibrarySetup() -> Phase {
        setup.showLibraryStep(error: nil)
        return .setup
    }

    private func connectLibrary(_ credentials: WebAPICredentials) {
        let clientID = credentials.clientID
        let api = WebAPIClient(
            auth: SpotifyAuth(clientID: clientID),
            tokens: credentials.tokens,
            // Called after every token refresh (hourly) so a restart keeps working.
            onTokensChanged: { tokens in
                try? WebAPICredentials(clientID: clientID, tokens: tokens).save()
            }
        )
        library = LibraryService(api: api)
        refreshLiked(for: playback.track)
    }

    /// Called by library views when a request fails. An expired login (after
    /// 6 months) sends the user back to setup step 4.
    func handleLibraryError(_ error: any Error) {
        log.error("Library request failed: \(error.localizedDescription, privacy: .public)")
        if case .reauthorizationRequired = error as? WebAPIError {
            library = nil
            setup.showLibraryStep(error: error.localizedDescription)
            phase = .setup
        }
    }

    private func refreshLiked(for track: Track?) {
        likeTask?.cancel()
        isCurrentTrackLiked = nil
        guard let library, let uri = track?.id else { return }
        likeTask = Task { [weak self] in
            do {
                let liked = try await library.isLiked(uri)
                guard !Task.isCancelled else { return }
                self?.isCurrentTrackLiked = liked
            } catch {
                self?.handleLibraryError(error)
            }
        }
    }

    /// Updates the heart immediately and reverts it if Spotify refuses.
    func toggleLike() {
        guard let library, let uri = playback.track?.id, let liked = isCurrentTrackLiked else {
            log.notice("Like ignored: library \(self.library != nil), liked state \(String(describing: self.isCurrentTrackLiked))")
            return
        }
        isCurrentTrackLiked = !liked
        Task {
            do {
                try await library.setLiked(!liked, trackURI: uri)
                // Ask Spotify for the result, so the log shows what really happened.
                let now = try await library.isLiked(uri)
                if playback.track?.id == uri { isCurrentTrackLiked = now }
                log.notice("\(liked ? "Unliked" : "Liked", privacy: .public) \(uri, privacy: .public); Spotify now reports liked = \(now)")
                likedSongsVersion += 1
            } catch {
                if playback.track?.id == uri { isCurrentTrackLiked = liked }
                handleLibraryError(error)
            }
        }
    }

    /// Settings in the `…` menu, and "Connect your library" when it was
    /// skipped: the setup step for the Spotify app's Client ID (Web API).
    func openLibrarySetup() {
        setup.beginSettingsChange(.library)
        phase = .setup
    }

    /// Settings in the `…` menu: enter a new Soloist API key. Playback keeps
    /// running with the old key until the new one is submitted.
    func openAPIKeySetup() {
        setup.beginSettingsChange(.key)
        phase = .setup
    }

    /// Plays a playlist or album from the start and shows the player.
    func play(uri: String) {
        send { try await $0.play(uri: uri) }
        page = .player
    }

    /// Plays `tracks[index]` and queues the next tracks of the list.
    func play(tracks: [TrackSummary], startingAt index: Int) {
        guard tracks.indices.contains(index) else { return }
        let first = tracks[index].uri
        let following = tracks.dropFirst(index + 1).prefix(Self.queuedFollowingTracks).map(\.uri)
        send { source in
            try await source.play(uri: first)
            for uri in following { try await source.addToQueue(uri: uri) }
        }
        page = .player
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

    /// 0–100.
    func setVolume(_ volume: Int) { send { try await $0.setVolume(volume) } }
    func toggleShuffle() {
        let enabled = !playback.shuffle
        send { try await $0.setShuffle(enabled) }
    }

    /// off → context (playlist/album) → track → off.
    func cycleRepeat() {
        let next: RepeatMode = switch playback.repeatMode {
        case .off: .context
        case .context: .track
        case .track: .off
        }
        send { try await $0.setRepeat(next) }
    }

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

    func setupHasLibrary() -> Bool {
        library != nil || UserDefaults.standard.bool(forKey: SetupModel.librarySkippedKey)
    }

    func setupConnectLibrary(_ credentials: WebAPICredentials) {
        connectLibrary(credentials)
    }
}
