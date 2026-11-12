import AuralCore
import SwiftUI

/// Plain Stage 2 player: cover, title, artist, time, play/pause and next.
/// The designed mini player (Liquid Glass) replaces this in Stage 4.
struct PlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 14) {
            artwork
            VStack(spacing: 4) {
                Text(model.playback.track?.title ?? "Nothing playing")
                    .font(.headline)
                    .lineLimit(1)
                Text(model.playback.track?.artists.joined(separator: ", ") ?? "Choose music in Spotify or play from here later")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            ElapsedTimeView(playback: model.playback)
            HStack(spacing: 24) {
                Button("Previous", systemImage: "backward.fill", action: model.previous)
                Button(model.playback.status == .playing ? "Pause" : "Play",
                       systemImage: model.playback.status == .playing ? "pause.fill" : "play.fill",
                       action: model.togglePlayPause)
                    .font(.title)
                Button("Next", systemImage: "forward.fill", action: model.next)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(model.playback.track == nil)

            HStack {
                Button("Library", systemImage: "music.note.list") { openWindow(id: "library") }
                Spacer()
                if model.library != nil {
                    Button(model.isCurrentTrackLiked == true ? "Remove from Liked Songs" : "Add to Liked Songs",
                           systemImage: model.isCurrentTrackLiked == true ? "heart.fill" : "heart",
                           action: model.toggleLike)
                        .labelStyle(.iconOnly)
                        .disabled(model.isCurrentTrackLiked == nil)
                }
            }
            .buttonStyle(.borderless)

            if let problem = model.problem {
                Text(problem).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(24)
        .frame(width: 340, height: 400)
    }

    @ViewBuilder private var artwork: some View {
        if let image = model.artwork {
            Image(decorative: image, scale: 2)
                .resizable()
                .frame(width: 150, height: 150)
                .clipShape(.rect(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10)
                .fill(.quaternary)
                .frame(width: 150, height: 150)
                .overlay { Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.secondary) }
        }
    }
}

/// Elapsed / total time, computed locally from the position anchor once per second.
private struct ElapsedTimeView: View {
    let playback: PlaybackState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = playback.track?.durationMs ?? 0
            let elapsed = playback.position.current(at: context.date, durationMs: duration)
            Text("\(Self.format(elapsed)) / \(Self.format(duration))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private static func format(_ ms: Int) -> String {
        Duration.milliseconds(ms).formatted(.time(pattern: .minuteSecond))
    }
}
