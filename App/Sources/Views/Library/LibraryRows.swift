import AuralCore
import SwiftUI

// Rows in the style of the iOS Music app: rounded covers, a regular-weight
// title with a dimmed subtitle, no chevrons, no separators, and the playing
// song marked with an animated waveform. On the Mac a row also highlights on hover (iOS's tap
// highlight).

struct TrackRow: View {
    @Environment(AppModel.self) private var model
    let track: TrackSummary
    /// Album pages show the track number instead of the (identical) cover.
    var number: Int?

    var body: some View {
        let isCurrent = model.playback.track?.id == track.uri
        let isPlaying = isCurrent && model.playback.status == .playing

        RowLayout(title: track.title, subtitle: track.artists.joined(separator: ", "), isCurrent: isCurrent) {
            if let number {
                ZStack {
                    if isCurrent {
                        NowPlayingIndicator(isPlaying: isPlaying)
                    } else {
                        Text("\(number)")
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
                .frame(width: 24)
            } else {
                Thumbnail(url: track.imageURL, size: RowMetrics.trackArtwork)
                    .overlay {
                        if isCurrent {
                            RoundedRectangle(cornerRadius: RowMetrics.cornerRadius).fill(.black.opacity(0.45))
                            NowPlayingIndicator(isPlaying: isPlaying)
                        }
                    }
            }
        } trailing: {
            Text(formatTime(track.durationMs))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

struct PlaylistRow: View {
    let playlist: PlaylistSummary

    var body: some View {
        RowLayout(
            title: playlist.name,
            subtitle: [playlist.ownerName, playlist.trackCount.map { "\($0) songs" }].compactMap { $0 }.joined(separator: " · ")
        ) {
            Thumbnail(url: playlist.imageURL, size: RowMetrics.collectionArtwork)
        }
    }
}

struct AlbumRow: View {
    let album: AlbumSummary

    var body: some View {
        RowLayout(title: album.name, subtitle: album.artists.joined(separator: ", ")) {
            Thumbnail(url: album.imageURL, size: RowMetrics.collectionArtwork)
        }
    }
}

struct ArtistRow: View {
    let artist: ArtistSummary

    var body: some View {
        RowLayout(title: artist.name, subtitle: "Artist") {
            Thumbnail(url: artist.imageURL, size: RowMetrics.collectionArtwork, circular: true)
        }
    }
}

private enum RowMetrics {
    static let trackArtwork: CGFloat = 44
    static let collectionArtwork: CGFloat = 52
    static let cornerRadius: CGFloat = 6
}

/// Shared layout of all rows.
private struct RowLayout<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String
    var isCurrent = false
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isRowSelected) private var isSelected
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            leading()
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 14))
                    .foregroundStyle(isCurrent ? Theme.accent : .white)
                    .lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(Theme.secondaryOpacity(contrast)))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .contentShape(.rect) // the whole row is clickable, not only the text
        .background {
            // Selected (the page opened last): a darker fill; hover: a lighter one.
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? .black.opacity(isHovered ? 0.14 : 0.2) : .white.opacity(isHovered ? 0.07 : 0))
                .padding(.horizontal, -8)
                .padding(.vertical, -4)
        }
        .onHover { isHovered = $0 }
        .animation(Theme.hoverAnimation, value: isHovered)
    }
}

extension RowLayout where Trailing == EmptyView {
    init(title: String, subtitle: String, isCurrent: Bool = false, @ViewBuilder leading: @escaping () -> Leading) {
        self.init(title: title, subtitle: subtitle, isCurrent: isCurrent, leading: leading, trailing: { EmptyView() })
    }
}

/// Animated bars for the song that is playing (still while paused).
private struct NowPlayingIndicator: View {
    let isPlaying: Bool

    var body: some View {
        Image(systemName: "waveform")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .symbolEffect(.variableColor.iterative, isActive: isPlaying)
            .accessibilityLabel(isPlaying ? "Playing" : "Paused")
    }
}

extension EnvironmentValues {
    /// Set by `PageLink` on the row whose page was opened last.
    @Entry var isRowSelected = false
}

extension View {
    /// List row chrome for the library: no row background (the tinted window
    /// background shows through), iOS-like insets, no separators.
    func libraryRow() -> some View {
        listRowInsets(EdgeInsets(top: 7, leading: 16, bottom: 7, trailing: 16))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// A list on the tinted background with room before the first and after
    /// the last row. (`contentMargins` has no effect on a macOS `List`; a
    /// safe-area inset does: the list scrolls under it and stops before it.)
    func libraryList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .top, spacing: 0) { Color.clear.frame(height: 8) }
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: 24) }
    }
}

/// Small cover image. The URL already points to Spotify's smallest suitable
/// size (~64 px), so the decoded image stays tiny; rows that scroll away
/// release theirs because `List` discards off-screen rows.
struct Thumbnail: View {
    let url: URL?
    let size: CGFloat
    var circular = false

    var body: some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            Rectangle().fill(.white.opacity(0.08))
                .overlay { Image(systemName: "music.note").foregroundStyle(.white.opacity(0.3)) }
        }
        .frame(width: size, height: size)
        .clipShape(circular ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: RowMetrics.cornerRadius)))
    }
}
