import AuralCore
import SwiftUI

/// The player page, following docs/design-2.png: track info, round cover with
/// a progress ring, icon controls and a glass play button. The tinted
/// background comes from `MainView`.
struct PlayerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Every row has a fixed height, and the gaps put each row's center
        // where the design has it (see `Metrics`), so nothing drifts with
        // font metrics. The rows fill the window exactly; no spacer.
        VStack(spacing: 0) {
            TrackInfo(track: model.playback.track)
                .padding(.top, Metrics.contentTop)
            TimeLabel(playback: model.playback)
                .frame(height: Metrics.timeHeight)
                .padding(.top, 25)
            CoverWithRing()
                // The time sits inside the ring's open top, as in the design.
                .padding(.top, -13)
            TransportControls()
                .frame(height: Metrics.transportHeight)
                .padding(.top, 30)
            BottomControls()
                .frame(height: Metrics.bottomRowHeight)
                .padding(.top, 33)
                .padding(.bottom, 15)
        }
        .padding(.horizontal, Metrics.sideInset)
        .foregroundStyle(.white)
        .overlay(alignment: .bottom) {
            if let problem = model.problem {
                Text(problem).font(.caption).foregroundStyle(.red).padding(.bottom, 8)
            }
        }
    }
}

/// Sizes measured on the left screen of docs/design-2.png (375 × 812 px) and
/// scaled to the 320 pt window width (× 0.853): ring, cover, icons, insets.
/// The window is shorter than the design (576 pt instead of 693 pt), so the
/// vertical gaps between rows are the design's gaps scaled to roughly 60%,
/// keeping their proportions to each other.
enum Metrics {
    static let windowSize = CGSize(width: 320, height: 576)
    /// Where every page's content starts, just below the toolbar (window
    /// buttons and the `…` menu). The same on the player, library and search.
    static let contentTop = 60.0
    /// Icons at the edges are centered 36 pt from the window sides.
    static let sideInset = 18.0
    static let titleHeight = 22.0
    static let artistHeight = 16.0
    static let titleArtistGap = 4.0
    static let timeHeight = 14.0
    /// Ring diameter at the stroke: 264 pt (309 px), plus the knob that sticks out.
    static let ringFrame = 278.0
    /// 225 pt (264 px): the gap to the ring is 19.5 pt, as in the design.
    static let coverSize = 225.0
    static let transportHeight = 56.0
    static let bottomRowHeight = 36.0
}

private struct TrackInfo: View {
    let track: Track?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Metrics.titleArtistGap) {
            Text(track?.title ?? "Nothing playing")
                .font(.title2.weight(.semibold))
                .lineLimit(1)
                .frame(height: Metrics.titleHeight)
            Text(track?.artists.joined(separator: ", ") ?? "Choose music from your library")
                .font(.callout)
                .foregroundStyle(.white.opacity(Theme.secondaryOpacity(contrast)))
                .lineLimit(1)
                .frame(height: Metrics.artistHeight)
        }
        .multilineTextAlignment(.center)
    }
}

/// `01:23 | 02:35`, updated once per second from the position anchor.
private struct TimeLabel: View {
    let playback: PlaybackState

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = playback.track?.durationMs ?? 0
            let elapsed = playback.position.current(at: context.date, durationMs: duration)
            HStack(spacing: 8) {
                Text(formatTime(elapsed)).foregroundStyle(.white.opacity(0.7))
                Rectangle().fill(.white.opacity(0.35)).frame(width: 1, height: 10)
                Text(formatTime(duration)).foregroundStyle(Theme.accent)
            }
            .font(.caption.monospacedDigit())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(formatTime(elapsed)) of \(formatTime(duration))")
        }
    }
}

private struct CoverWithRing: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            cover
                .frame(width: Metrics.coverSize, height: Metrics.coverSize)
                .clipShape(.circle)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            // Only the ring redraws every frame, and only while playing.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: model.playback.status != .playing)) { context in
                let duration = model.playback.track?.durationMs ?? 0
                let elapsed = model.playback.position.current(at: context.date, durationMs: duration)
                ProgressRing(
                    progress: duration > 0 ? Double(elapsed) / Double(duration) : 0,
                    durationMs: duration,
                    canSeek: model.playback.availableActions.contains(.seek),
                    onSeek: model.seek(toMs:)
                )
            }
        }
        .frame(width: Metrics.ringFrame, height: Metrics.ringFrame)
    }

    @ViewBuilder private var cover: some View {
        if let image = model.artwork {
            Image(decorative: image, scale: 2).resizable().scaledToFill()
        } else {
            Circle().fill(.white.opacity(0.08))
                .overlay { Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white.opacity(0.4)) }
        }
    }
}
