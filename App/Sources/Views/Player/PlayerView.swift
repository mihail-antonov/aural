import AuralCore
import SwiftUI

/// The player page, following docs/design-2.png: a header row (device,
/// playlist / album, heart), track info, round cover with a progress ring,
/// icon controls and a glass play button. The tinted
/// background comes from `MainView`.
struct PlayerView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // Three parts, so changing one never moves the others:
        // - top: header and track info, at fixed distances from the window top;
        // - bottom: the two control rows, at fixed distances from the bottom;
        // - middle: the time and the cover with its ring, which take the
        //   space left and shrink (never below the gaps) if it gets tighter.
        VStack(spacing: 0) {
            // Starts where every page's content starts.
            PlayerHeader()
                .frame(height: Metrics.headerHeight)
                .padding(.top, Metrics.contentTop)
            TrackInfo(track: model.playback.track)
                .padding(.top, Metrics.headerToTitle)

            GeometryReader { proxy in
                let ring = Metrics.ringSize(fitting: proxy.size.height)
                VStack(spacing: 0) {
                    TimeLabel(playback: model.playback)
                        .frame(height: Metrics.timeHeight)
                        .padding(.top, Metrics.titleToTime)
                    CoverWithRing(ringSize: ring)
                        // The time sits inside the ring's open top, as in the design.
                        .padding(.top, -Metrics.timeInRing)
                }
                .frame(maxWidth: .infinity)
            }

            TransportControls()
                .frame(height: Metrics.transportHeight)
            BottomControls()
                .frame(height: Metrics.bottomRowHeight)
                .padding(.top, Metrics.transportToBottomRow)
                .padding(.bottom, Metrics.bottomInset)
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
/// The window is shorter than the design (638 pt instead of 693 pt); the
/// player's layout is anchored to the top and bottom (see `PlayerView`).
enum Metrics {
    /// The whole window, title bar included.
    static let windowSize = CGSize(width: 320, height: 638)
    /// The hidden title bar with the toolbar (window buttons, `…` menu).
    /// The content runs under it, but macOS adds it to the content's size.
    static let titleBarHeight = 52.0
    /// Where every page's content starts, just below the toolbar (window
    /// buttons and the `…` menu). The same on the player, library and search.
    static let contentTop = 60.0
    /// Icons at the edges are centered 36 pt from the window sides.
    static let sideInset = 18.0
    static let headerHeight = 28.0
    static let titleHeight = 22.0
    static let artistHeight = 16.0
    static let titleArtistGap = 4.0
    static let timeHeight = 14.0
    /// Largest ring: diameter at the stroke 264 pt (309 px), plus the knob
    /// that sticks out.
    static let ringFrame = 278.0
    /// Cover size relative to the ring: 225 pt in a 278 pt ring (the gap to
    /// the ring is 19.5 pt, as in the design).
    static let coverToRing = 225.0 / 278.0
    static let transportHeight = 56.0
    static let bottomRowHeight = 36.0

    // Vertical gaps. The control rows keep the design's spacing; only the
    // ring adapts to the space left between the track info and the controls.
    static let headerToTitle = 16.0
    static let titleToTime = 24.0
    /// How far the time reaches into the ring's open top.
    static let timeInRing = 13.0
    /// Smallest gap between the ring and the controls row.
    static let ringToTransport = 34.0
    static let transportToBottomRow = 33.0
    /// The bottom row's distance to the window edge (about where the design
    /// has it, scaled to this window).
    static let bottomInset = 40.0

    /// The ring as large as fits in the middle area (at most `ringFrame`).
    static func ringSize(fitting height: Double) -> Double {
        let ringTop = titleToTime + timeHeight - timeInRing
        return max(0, min(ringFrame, height - ringTop - ringToTransport))
    }
}

private struct TrackInfo: View {
    let track: Track?
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(spacing: Metrics.titleArtistGap) {
            // Long titles scroll sideways, like Spotify's.
            MarqueeText(text: track?.title ?? "Nothing playing", font: .title2.weight(.semibold))
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

/// The design's top row: where the music plays (left, instead of the
/// design's chevron), the playlist or album (middle) and the heart (right,
/// instead of the design's `…`). Equal side slots keep the name centered.
private struct PlayerHeader: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorSchemeContrast) private var contrast

    private static let sideSlot = 84.0

    var body: some View {
        let playback = model.playback
        HStack(spacing: 0) {
            DeviceMenu(playback: playback)
                .frame(width: Self.sideSlot, alignment: .leading)
            Text(playback.contextName ?? "")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.white.opacity(Theme.secondaryOpacity(contrast)))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
            LikeButton()
                .frame(width: Self.sideSlot, alignment: .trailing)
        }
    }
}

/// Where the music plays: a speaker icon with a dropdown, in the accent
/// color while Aural (Soloist) is Spotify's active device, dimmed white
/// while another device plays. The menu offers "Playing in Spotify" /
/// "Playing in Aural"; picking Aural takes playback over.
/// (Soloist does not say which other device; only shown while something is loaded.)
private struct DeviceMenu: View {
    @Environment(AppModel.self) private var model
    let playback: PlaybackState

    var body: some View {
        if playback.track != nil {
            let isHere = playback.isActiveDevice
            Menu {
                // Menu items with the system's checkmark (a `Toggle` in a menu).
                // Only "Playing in Aural" does something: it takes playback
                // over. "Playing in Spotify" just shows the state, so it is
                // always disabled (Aural cannot pick another device).
                Toggle("Playing in Spotify", isOn: .constant(!isHere))
                    .disabled(true)
                Toggle("Playing in Aural", isOn: Binding(
                    get: { isHere },
                    set: { playHere in if playHere { model.playHere() } }
                ))
                .disabled(isHere)
            } label: {
                Label(isHere ? "Playing in Aural" : "Playing in Spotify", systemImage: "hifispeaker")
            }
            .menuStyle(.button)
            .buttonStyle(IconButtonStyle(size: 15, frame: 28))
            .labelStyle(.iconOnly)
            .menuIndicator(.hidden)
            .iconActive(isHere)
            .tooltip(isHere ? "Playing in Aural" : "Playing in Spotify")
        }
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
    let ringSize: Double

    var body: some View {
        ZStack {
            cover
                .frame(width: ringSize * Metrics.coverToRing, height: ringSize * Metrics.coverToRing)
                .clipShape(.circle)
                .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
            // Only the ring redraws every frame, and only while playing.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: model.playback.status != .playing)) { context in
                let duration = model.playback.track?.durationMs ?? 0
                let elapsed = model.playback.position.current(at: context.date, durationMs: duration)
                ProgressRing(
                    progress: duration > 0 ? Double(elapsed) / Double(duration) : 0,
                    trackID: model.playback.track?.id,
                    durationMs: duration,
                    canSeek: model.playback.availableActions.contains(.seek),
                    onSeek: model.seek(toMs:)
                )
            }
        }
        .frame(width: ringSize, height: ringSize)
    }

    /// When the track changes, the old cover fades out right away; the new
    /// one fades in once it has loaded. The image is swapped while invisible,
    /// so it never snaps. A faint circle stays behind as the placeholder.
    private var cover: some View {
        let isCurrent = model.artworkTrackID != nil && model.artworkTrackID == model.playback.track?.id
        return ZStack {
            Circle().fill(.white.opacity(0.08))
            if let image = model.artwork {
                Image(decorative: image, scale: 2).resizable().scaledToFill()
                    .opacity(isCurrent ? 1 : 0)
                    .scaleEffect(isCurrent ? 1 : 0.96)
            } else if isCurrent || model.playback.track == nil {
                // The track has no cover at all.
                Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white.opacity(0.4))
            }
        }
        .animation(.easeInOut(duration: 0.35), value: isCurrent)
    }
}
