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
    /// What plays next (the Queue page).
    private(set) var queue = PlaybackQueue()
    /// Cover of the current track. Kept from the previous track until the
    /// new one has loaded, so the player can cross-fade instead of flashing
    /// an empty placeholder (at most two covers, ~0.8 MB each, briefly).
    private(set) var artwork: CGImage?
    /// The track `artwork` belongs to; the player cross-fades when it changes.
    private(set) var artworkTrackID: String?
    /// Average color of the current cover, for the tinted background. Kept
    /// from the previous track until the new cover has loaded.
    private(set) var coverColor: ArtworkColor?
    private(set) var isLoggedIn = false
    /// Shown in the player when something went wrong (e.g. Soloist stopped).
    private(set) var problem: String?

    /// Whether the play button shows "pause". Follows the playback status,
    /// but Soloist briefly reports a non-playing status while it switches
    /// tracks; showing that would make the button flicker. So a change to
    /// "not playing" is applied after a short delay (unless the user paused).
    private(set) var showsPlaying = false

    /// Spotify Web API access (library, search, likes). Nil until connected.
    private(set) var library: LibraryService?
    /// Last known Liked Songs state, with the track it belongs to.
    private var likedState: (uri: String, liked: Bool)?
    /// Whether the current track is in Liked Songs; nil while unknown.
    var isCurrentTrackLiked: Bool? {
        guard let likedState, likedState.uri == playback.track?.id else { return nil }
        return likedState.liked
    }
    /// For the player's icon: the previous track's state is kept until the
    /// new one is known, so the icon does not flash between tracks.
    var showsLiked: Bool { likedState?.liked ?? false }
    /// Increases after every like/unlike so the Liked Songs list can reload.
    private(set) var likedSongsVersion = 0
    /// Increases after an album or playlist is saved / removed, so the
    /// library's lists can reload.
    private(set) var savedCollectionsVersion = 0

    /// Pages of the main window, opened from the player's bottom row
    /// (search, library, queue); their back chevron (or Esc) returns to
    /// the player.
    enum Page {
        case player, library, queue, search
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
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    /// Set when the user presses play / pause, until Soloist confirms it.
    @ObservationIgnored private var userPlayIntent: Bool?
    /// Tracks known to be in Liked Songs because they were played from it.
    /// Their heart shows right away. Bounded by the loaded Liked Songs list.
    @ObservationIgnored private var knownLikedURIs: Set<String> = []

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
        queue = PlaybackQueue()
    }

    private func handle(_ event: PlaybackEvent) {
        switch event {
        case .stateChanged(let state):
            let trackChanged = state.track?.id != playback.track?.id
            playback = state
            updateShowsPlaying(for: state.status)
            if trackChanged {
                loadArtwork(for: state.track)
                refreshLiked(for: state.track)
            }
            // Never show the previous track's cover in Control Center.
            nowPlaying?.update(state, artwork: artworkTrackID == state.track?.id ? artwork : nil)
        case .queueChanged(let newQueue):
            queue = newQueue
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
        guard let url = track?.artworkURL else {
            artwork = nil
            artworkTrackID = track?.id
            return
        }
        artworkTask = Task { [weak self] in
            guard let image = try? await ArtworkLoader.load(url, maxPixelSize: Self.artworkPixelSize),
                  !Task.isCancelled, let self
            else { return }
            artwork = image // replaces (and releases) the previous cover
            artworkTrackID = track?.id
            coverColor = ArtworkLoader.averageColor(of: image)
            nowPlaying?.update(playback, artwork: image)
        }
    }

    private func updateShowsPlaying(for status: PlaybackStatus) {
        // Buffering means "about to play", e.g. right after a skip.
        let isPlaying = status == .playing || status == .buffering
        if let intent = userPlayIntent {
            // The user just pressed play / pause: wait for Soloist to confirm.
            if isPlaying == intent { settleTask?.cancel(); userPlayIntent = nil; showsPlaying = isPlaying }
            return
        }
        if isPlaying {
            settleTask?.cancel()
            settleTask = nil
            showsPlaying = true
        } else if showsPlaying, settleTask == nil {
            settleShowsPlaying(after: .milliseconds(700))
        }
    }

    /// After `delay`, shows the real status (if nothing confirmed it earlier).
    private func settleShowsPlaying(after delay: Duration) {
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            settleTask = nil
            userPlayIntent = nil
            showsPlaying = playback.status == .playing || playback.status == .buffering
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
            setup.requireLibraryLogin(error: error.localizedDescription)
            phase = .setup
        }
    }

    /// Asks Spotify whether the new track is liked. Until it answers, the
    /// icon keeps the previous state (no flash), and tracks played from
    /// Liked Songs show as liked right away.
    private func refreshLiked(for track: Track?) {
        likeTask?.cancel()
        guard let library, let uri = track?.id else { return }
        if knownLikedURIs.contains(uri) { likedState = (uri, true) }
        likeTask = Task { [weak self] in
            do {
                let liked = try await library.isSaved(uri)
                guard !Task.isCancelled else { return }
                self?.likedState = (uri, liked)
            } catch {
                self?.handleLibraryError(error)
            }
        }
    }

    /// Adds the current track to Liked Songs or removes it. Updates the icon
    /// immediately and reverts it if Spotify refuses.
    func toggleLike() {
        guard let library, let uri = playback.track?.id, let liked = isCurrentTrackLiked else {
            log.notice("Like ignored: library \(self.library != nil), liked state \(String(describing: self.isCurrentTrackLiked))")
            return
        }
        likedState = (uri, !liked)
        if liked { knownLikedURIs.remove(uri) }
        Task {
            do {
                try await library.setSaved(!liked, uri: uri)
                // Ask Spotify for the result, so the log shows what really happened.
                let now = try await library.isSaved(uri)
                if likedState?.uri == uri { likedState = (uri, now) }
                log.notice("\(liked ? "Unliked" : "Liked", privacy: .public) \(uri, privacy: .public); Spotify now reports liked = \(now)")
                likedSongsVersion += 1
            } catch {
                if likedState?.uri == uri { likedState = (uri, liked) }
                handleLibraryError(error)
            }
        }
    }

    enum SaveOutcome {
        /// The item's state in the library afterwards.
        case saved(Bool)
        /// Spotify refused (403): e.g. saving a playlist may need a scope
        /// Aural does not ask for. The button hides itself.
        case notAllowed
        case failed
    }

    /// Saves an album or playlist to the library, or removes it.
    func setSaved(_ saved: Bool, uri: String) async -> SaveOutcome {
        guard let library else { return .failed }
        do {
            try await library.setSaved(saved, uri: uri)
            let now = try await library.isSaved(uri)
            savedCollectionsVersion += 1
            return .saved(now)
        } catch .forbidden(let message) {
            log.notice("Saving \(uri, privacy: .public) not allowed: \(message, privacy: .public)")
            return .notAllowed
        } catch {
            handleLibraryError(error)
            return .failed
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

    /// Plays a playlist or album and shows the player. `shuffled` sets
    /// shuffle before and after starting (Soloist may only accept it once the
    /// new playlist or album is loaded).
    func play(uri: String, shuffled: Bool) {
        send { source in
            try await source.setShuffle(shuffled)
            try await source.play(uri: uri)
            try await source.setShuffle(shuffled)
        }
        page = .player
    }

    /// Plays `tracks[index]` and then the rest of the list in order, and
    /// shows the player. `fromLikedSongs`: the tracks are known to be liked.
    func play(tracks: [TrackSummary], startingAt index: Int, fromLikedSongs: Bool = false) {
        guard tracks.indices.contains(index) else { return }
        knownLikedURIs = fromLikedSongs ? Set(tracks.map(\.uri)) : []
        let playable = tracks.map(\.track)
        send { try await $0.play(tracks: playable, startingAt: index) }
        page = .player
    }

    // MARK: - Commands

    /// Uses what the button shows, and switches it right away.
    func togglePlayPause() {
        let play = !showsPlaying
        showsPlaying = play
        userPlayIntent = play
        // If Soloist never confirms (e.g. nothing to resume), show the truth.
        settleShowsPlaying(after: .seconds(2))
        if play {
            send { try await $0.resume() }
        } else {
            send { try await $0.pause() }
        }
    }

    func next() { send { try await $0.next() } }
    /// Takes playback over from another Spotify device.
    func playHere() { send { try await $0.playHere() } }

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
    func clearQueue() { send { try await $0.clearQueue() } }
    /// Plays an upcoming track from the Queue page (stays on that page).
    func jump(to entry: QueueEntry) {
        let id = entry.id
        send { try await $0.jump(toQueueEntry: id) }
    }
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
