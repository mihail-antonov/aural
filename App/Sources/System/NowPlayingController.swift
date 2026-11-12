import AppKit
import AuralCore
import MediaPlayer

/// Publishes the current track to macOS Now Playing (Control Center, lock
/// screen) and receives media keys / AirPods commands.
@MainActor
final class NowPlayingController {
    private let center = MPNowPlayingInfoCenter.default()
    private let commands = MPRemoteCommandCenter.shared()
    private var lastTrackID: String?
    private var lastArtwork: MPMediaItemArtwork?

    init(
        togglePlayPause: @escaping @MainActor () -> Void,
        play: @escaping @MainActor () -> Void,
        pause: @escaping @MainActor () -> Void,
        next: @escaping @MainActor () -> Void,
        previous: @escaping @MainActor () -> Void,
        seek: @escaping @MainActor (TimeInterval) -> Void
    ) {
        Self.register(commands.togglePlayPauseCommand) { _ in togglePlayPause() }
        Self.register(commands.playCommand) { _ in play() }
        Self.register(commands.pauseCommand) { _ in pause() }
        Self.register(commands.nextTrackCommand) { _ in next() }
        Self.register(commands.previousTrackCommand) { _ in previous() }
        Self.register(commands.changePlaybackPositionCommand) { event in
            if let event = event as? MPChangePlaybackPositionCommandEvent { seek(event.positionTime) }
        }
    }

    /// Remote command handlers may be called off the main thread, so each one
    /// hops to the main actor before touching app state.
    /// `nonisolated`: a closure written inside main-actor code is itself treated
    /// as main-actor-only, and Swift 6 traps when the system calls it from a
    /// background queue. Created here, the handler may run on any thread.
    private nonisolated static func register(
        _ command: MPRemoteCommand,
        action: @escaping @MainActor (MPRemoteCommandEvent) -> Void
    ) {
        command.isEnabled = true
        command.addTarget { event in
            nonisolated(unsafe) let event = event // only read inside the main-actor task
            Task { @MainActor in action(event) }
            return .success
        }
    }

    func update(_ state: PlaybackState, artwork: CGImage?) {
        guard let track = state.track else {
            clear()
            return
        }
        if track.id != lastTrackID {
            lastTrackID = track.id
            lastArtwork = nil
        }
        if lastArtwork == nil, let artwork {
            lastArtwork = Self.mediaArtwork(from: artwork)
        }

        let durationMs = track.durationMs
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artists.joined(separator: ", "),
            MPMediaItemPropertyPlaybackDuration: Double(durationMs) / 1000,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: Double(state.position.current(durationMs: durationMs)) / 1000,
            // The system advances the elapsed time itself while the rate is 1.
            MPNowPlayingInfoPropertyPlaybackRate: state.status == .playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        if let album = track.album { info[MPMediaItemPropertyAlbumTitle] = album }
        if let lastArtwork { info[MPMediaItemPropertyArtwork] = lastArtwork }

        center.nowPlayingInfo = info
        center.playbackState = switch state.status {
        case .playing, .buffering: .playing
        case .paused: .paused
        case .idle: .stopped
        }
    }

    func clear() {
        lastTrackID = nil
        lastArtwork = nil
        center.nowPlayingInfo = nil
        center.playbackState = .stopped
    }

    /// `nonisolated` for the same reason as `register`: MediaPlayer calls the
    /// request handler on its own background queue. It only reads the immutable image.
    private nonisolated static func mediaArtwork(from image: CGImage) -> MPMediaItemArtwork {
        let size = CGSize(width: image.width, height: image.height)
        return MPMediaItemArtwork(boundsSize: size) { _ in
            NSImage(cgImage: image, size: size)
        }
    }
}
