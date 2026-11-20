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
                // Starts at the row's edge, like the covers in other lists;
                // wide enough for two digits or the playing indicator.
                .frame(width: 20, alignment: .leading)
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

/// A song in the queue (or the one playing), from the playback source.
struct QueueRow: View {
    @Environment(AppModel.self) private var model
    let track: Track
    var isCurrent = false

    var body: some View {
        RowLayout(title: track.title, subtitle: track.artists.joined(separator: ", "), isCurrent: isCurrent) {
            Thumbnail(url: track.thumbnailURL ?? track.artworkURL, size: RowMetrics.trackArtwork)
                .overlay {
                    if isCurrent {
                        RoundedRectangle(cornerRadius: RowMetrics.cornerRadius).fill(.black.opacity(0.45))
                        NowPlayingIndicator(isPlaying: model.playback.status == .playing)
                    }
                }
        } trailing: {
            Text(formatTime(track.durationMs))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
        }
    }
}

/// What an empty page or list says: the system `ContentUnavailableView`
/// (icon, title, short description).
struct EmptyState {
    let title: String
    let systemImage: String
    let message: String

    var view: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

extension View {
    /// Shows `state` centered on the page (within the bars) while `isEmpty`.
    func emptyState(_ state: EmptyState, when isEmpty: Bool) -> some View {
        overlay {
            if isEmpty { state.view }
        }
    }
}

/// Title of a native list `Section` (header: { ListSectionHeader(...) }).
/// macOS draws it (small, grey, pinned on a blurred bar while its rows
/// scroll); only the text is indented like the rows (`libraryRow`'s 16 pt).
///
/// It also keeps the page bar's blur neutral: pinned right under the bar, it
/// is what the bar's scroll edge effect sees. Without a title, a cover sat
/// directly under the bar and its color bled into the blur.
///
/// The space above and below a section belongs to its title, not to the
/// rows: a macOS `List` centers a row's content in the row, so extra inset
/// on one side of the first or last row showed up split on both sides (the
/// first row looked farther from the second than the others).
struct ListSectionHeader: View {
    let title: String

    init(title: String) {
        self.title = title
    }

    /// The number of items on Spotify, e.g. "48 Playlists" (just "Playlists"
    /// until the first page has loaded).
    init(count: Int?, one: String, many: String) {
        title = count.map { "\($0) \($0 == 1 ? one : many)" } ?? many
    }

    var body: some View {
        Text(title)
            .padding(.horizontal, 16)
            .padding(.top, LibrarySpacing.aboveSection)
            .padding(.bottom, LibrarySpacing.belowSectionTitle)
    }
}

private enum RowMetrics {
    static let trackArtwork: CGFloat = 44
    static let collectionArtwork: CGFloat = 52
    static let cornerRadius: CGFloat = 6
    /// Space above and below a row's content (`libraryRow`).
    static let verticalInset: CGFloat = 7
}

/// Space around the library's lists and sections.
enum LibrarySpacing {
    /// Above every section title: from the page bar to the first title, and
    /// between sections (e.g. Songs and Artists in search).
    static let aboveSection: CGFloat = 16
    /// From a section title down to its first row (plus the row's inset).
    static let belowSectionTitle: CGFloat = 4
    /// Added after each group of search results (Songs, Artists, …).
    static let betweenSearchGroups: CGFloat = 16
    /// After the last row, the same as above the first section title.
    static let listEnd: CGFloat = aboveSection
}

/// Heights of whole rows: the cover plus `libraryRow`'s space above and below.
enum LibraryRowHeight {
    /// Songs with a cover (Liked, playlists, queue, artists).
    static let track = RowMetrics.trackArtwork + 2 * RowMetrics.verticalInset
    /// Playlists and albums.
    static let collection = RowMetrics.collectionArtwork + 2 * RowMetrics.verticalInset
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
    /// background shows through), iOS-like insets, no separators. The same
    /// for every row; space around sections comes from `ListSectionHeader`.
    func libraryRow() -> some View {
        listRowInsets(EdgeInsets(
            top: RowMetrics.verticalInset, leading: 16,
            bottom: RowMetrics.verticalInset, trailing: 16
        ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// Tells the list its rows' height up front. A macOS `List` lays new rows
    /// out at an estimated height and then corrects the scroll position to
    /// their real one, which made scrolling stutter where they differed.
    func libraryRowHeight(_ height: CGFloat) -> some View {
        environment(\.defaultMinListRowHeight, height)
    }

    /// A list on the tinted background with room after the last row. (Room
    /// before the first row comes from the first section title: a top inset
    /// would leave a strip above the pinned title where rows scroll through.
    /// `contentMargins` has no effect on a macOS `List`; a safe-area inset
    /// does: the list scrolls under it and stops before it.)
    func libraryList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom, spacing: 0) { Color.clear.frame(height: LibrarySpacing.listEnd) }
    }
}

/// Small cover image. The URL already points to Spotify's smallest suitable
/// size (~64 px), so the decoded image stays tiny; rows that scroll away
/// release theirs because `List` discards off-screen rows. Files come from
/// the disk cache after the first load (`ArtworkImage`).
struct Thumbnail: View {
    let url: URL?
    let size: CGFloat
    var circular = false

    var body: some View {
        ArtworkImage(url: url, size: size) {
            Rectangle().fill(.white.opacity(0.08))
                .overlay { Image(systemName: "music.note").foregroundStyle(.white.opacity(0.3)) }
        }
        .clipShape(circular ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: RowMetrics.cornerRadius)))
    }
}
