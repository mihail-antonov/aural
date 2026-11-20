import AuralCore
import SwiftUI

struct PlaylistDetailView: View {
    let playlist: PlaylistSummary
    let model: AppModel
    /// Nil for playlists whose tracks Spotify does not share.
    @State private var tracks: PagedList<TrackSummary>?

    init(playlist: PlaylistSummary, model: AppModel) {
        self.playlist = playlist
        self.model = model
        // Created here, not in `.task`: the page must have its final content
        // when it starts sliding in. Swapping it in a moment later showed
        // "Tracks not available" briefly, and the new list appeared in place
        // instead of sliding with the page.
        _tracks = State(initialValue: playlist.canListTracks ? model.library.map { library in
            PagedList(load: { try await library.playlistTracks(playlist, offset: $0) }, onError: model.handleLibraryError)
        } : nil)
    }

    var body: some View {
        Group {
            if let tracks {
                PagedListView(list: tracks, empty: EmptyState(
                    title: "No Songs", systemImage: "music.note", message: "This playlist is empty."
                )) {
                    header
                } row: { index, track in
                    Button { model.play(tracks: tracks.items, startingAt: index) } label: { TrackRow(track: track) }
                        .buttonStyle(.plain)
                }
                .libraryRowHeight(LibraryRowHeight.track)
            } else {
                List {
                    // A section title above the cover, as in `PagedListView`.
                    Section {
                        header.libraryRow()
                        ContentUnavailableView(
                            "Tracks not available",
                            systemImage: "lock",
                            description: Text("Spotify only shares the tracks of playlists you own or collaborate on. You can still play this playlist.")
                        )
                        .libraryRow()
                    } header: {
                        ListSectionHeader(count: playlist.trackCount, one: "Song", many: "Songs")
                    }
                }
                .libraryList()
            }
        }
    }

    private var header: some View {
        CollectionHeader(
            imageURL: playlist.coverURL ?? playlist.imageURL,
            title: playlist.name,
            subtitle: playlist.ownerName.map { "Playlist · \($0)" } ?? "Playlist",
            details: tracks.flatMap { CollectionHeader.details(of: $0) }
                ?? playlist.trackCount.map { CollectionHeader.details(count: $0, durationMs: nil) },
            // The user's own playlists are always in their library.
            saveURI: playlist.isOwnedByUser ? nil : playlist.uri,
            play: { model.play(uri: playlist.uri, shuffled: false) },
            shuffle: { model.play(uri: playlist.uri, shuffled: true) }
        )
    }
}

struct AlbumDetailView: View {
    let album: AlbumSummary
    let model: AppModel
    @State private var tracks: PagedList<TrackSummary>?

    init(album: AlbumSummary, model: AppModel) {
        self.album = album
        self.model = model
        // Created here, not in `.task`: a view whose body is empty never
        // appears, so its `.task` would never run and the page stayed blank.
        _tracks = State(initialValue: model.library.map { library in
            PagedList(load: { try await library.albumTracks(album, offset: $0) }, onError: model.handleLibraryError)
        })
    }

    var body: some View {
        Group {
            if let tracks {
                PagedListView(list: tracks, empty: EmptyState(
                    title: "No Songs", systemImage: "music.note", message: "Spotify has no songs for this album."
                )) {
                    CollectionHeader(
                        imageURL: album.coverURL ?? album.imageURL,
                        title: album.name,
                        subtitle: album.artists.joined(separator: ", "),
                        details: CollectionHeader.details(of: tracks),
                        saveURI: album.uri,
                        play: { model.play(uri: album.uri, shuffled: false) },
                        shuffle: { model.play(uri: album.uri, shuffled: true) }
                    )
                } row: { index, track in
                    Button { model.play(tracks: tracks.items, startingAt: index) } label: { TrackRow(track: track, number: index + 1) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Soloist cannot play an artist, so the artist page lists their tracks (from search).
struct ArtistDetailView: View {
    let artist: ArtistSummary
    let model: AppModel
    @State private var tracks: PagedList<TrackSummary>?

    init(artist: ArtistSummary, model: AppModel) {
        self.artist = artist
        self.model = model
        // Created here for the same reason as on the album page.
        _tracks = State(initialValue: model.library.map { library in
            PagedList(load: { try await library.tracks(by: artist, offset: $0) }, onError: model.handleLibraryError)
        })
    }

    var body: some View {
        Group {
            if let tracks {
                PagedListView(list: tracks, empty: EmptyState(
                    title: "No Songs", systemImage: "music.mic", message: "Spotify found no songs by this artist."
                )) {
                    CollectionHeader(
                        imageURL: artist.imageURL,
                        title: artist.name,
                        subtitle: "Artist",
                        isCircular: true,
                        canPlay: !tracks.items.isEmpty,
                        play: { model.play(tracks: tracks.items, startingAt: 0) },
                        shuffle: { model.play(tracks: tracks.items.shuffled(), startingAt: 0) }
                    )
                } row: { index, track in
                    Button { model.play(tracks: tracks.items, startingAt: index) } label: { TrackRow(track: track) }
                        .buttonStyle(.plain)
                }
                .libraryRowHeight(LibraryRowHeight.track)
            }
        }
    }
}

/// Top of a playlist / album / artist page (and Liked Songs), like iOS Music:
/// a large cover, the title, a subtitle and the song count with the total
/// time, then round system Liquid Glass buttons — Play (accent icon),
/// Shuffle and, for albums and other people's playlists, Save to Library.
struct CollectionHeader: View {
    let imageURL: URL?
    let title: String
    let subtitle: String
    /// "12 songs, 48 min 3 sec".
    var details: String?
    var isCircular = false
    var canPlay = true
    /// Album or playlist URI for the save button; nil hides it.
    var saveURI: String?
    let play: () -> Void
    let shuffle: () -> Void

    private static let coverSize: CGFloat = 140

    var body: some View {
        VStack(spacing: 6) {
            ArtworkImage(url: imageURL, size: Self.coverSize) {
                Rectangle().fill(.white.opacity(0.08))
                    .overlay { Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white.opacity(0.3)) }
            }
            .clipShape(isCircular ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: 10)))
            .shadow(color: .black.opacity(0.3), radius: 10, y: 5)
            .padding(.bottom, 6)

            Text(title)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(subtitle)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
                .lineLimit(1)
            if let details {
                Text(details)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }

            // Nearby glass buttons are grouped, so they render together.
            GlassEffectContainer {
                HStack(spacing: 14) {
                    if let saveURI {
                        SaveToLibraryButton(uri: saveURI)
                    }
                    // Plain system glass like Shuffle; the peach icon marks the main action.
                    Button(action: play) {
                        icon("play.fill").foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.glass)
                    .accessibilityLabel("Play")
                    .tooltip("Play")
                    .disabled(!canPlay)
                    Button(action: shuffle) { icon("shuffle") }
                        .buttonStyle(.glass)
                        .accessibilityLabel("Shuffle")
                        .tooltip("Shuffle")
                        .disabled(!canPlay)
                }
                .buttonBorderShape(.circle)
                .controlSize(.extraLarge)
                .foregroundStyle(.white)
            }
            .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 10)
    }

    /// "12 songs, 48 min 3 sec" once every page has loaded; only the count before.
    static func details(of tracks: PagedList<TrackSummary>) -> String? {
        guard let total = tracks.total else { return nil }
        return details(count: total, durationMs: tracks.isComplete ? tracks.items.reduce(0) { $0 + $1.durationMs } : nil)
    }

    static func details(count: Int, durationMs: Int?) -> String {
        let songs = count == 1 ? "1 song" : "\(count) songs"
        guard let durationMs, durationMs > 0 else { return songs }
        let seconds = durationMs / 1000
        let (hours, minutes) = (seconds / 3600, seconds % 3600 / 60)
        // Like Spotify: hours and minutes for long lists, otherwise minutes and seconds.
        let time = hours > 0 ? "\(hours) hr \(minutes) min" : "\(minutes) min \(seconds % 60) sec"
        return "\(songs), \(time)"
    }

    private func icon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 30, height: 30)
    }
}

/// "+" / check button that saves an album or playlist to the user's library
/// (like Spotify's), or removes it.
private struct SaveToLibraryButton: View {
    @Environment(AppModel.self) private var model
    let uri: String
    /// Nil while unknown (loading, or the check failed).
    @State private var isSaved: Bool?
    @State private var isBusy = false
    /// Spotify refused to save this item (see `AppModel.SaveOutcome`).
    @State private var isNotAllowed = false

    var body: some View {
        if !isNotAllowed { button }
    }

    private var button: some View {
        Button {
            guard let isSaved else { return }
            isBusy = true
            Task {
                switch await model.setSaved(!isSaved, uri: uri) {
                case .saved(let now): self.isSaved = now
                case .notAllowed: withAnimation { isNotAllowed = true }
                case .failed: break
                }
                isBusy = false
            }
        } label: {
            Image(systemName: isSaved == true ? "checkmark" : "plus")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSaved == true ? Theme.accent : .white)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .disabled(isSaved == nil || isBusy)
        .accessibilityLabel(isSaved == true ? "Remove from Library" : "Save to Library")
        .tooltip(isSaved == true ? "Remove from Library" : "Save to Library")
        .task(id: uri) {
            guard let library = model.library else { return }
            isSaved = try? await library.isSaved(uri)
        }
    }
}
