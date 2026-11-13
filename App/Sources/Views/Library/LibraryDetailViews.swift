import AuralCore
import SwiftUI

struct PlaylistDetailView: View {
    let playlist: PlaylistSummary
    let model: AppModel
    @State private var tracks: PagedList<TrackSummary>?

    var body: some View {
        Group {
            if let tracks {
                PagedListView(list: tracks) {
                    header
                } row: { index, track in
                    Button { model.play(tracks: tracks.items, startingAt: index) } label: { TrackRow(track: track) }
                        .buttonStyle(.plain)
                }
            } else {
                List {
                    header.libraryRow()
                    ContentUnavailableView(
                        "Tracks not available",
                        systemImage: "lock",
                        description: Text("Spotify only shares the tracks of playlists you own or collaborate on. You can still play this playlist.")
                    )
                    .libraryRow()
                }
                .libraryList()
            }
        }
        .navigationTitle(playlist.name)
        .task {
            guard tracks == nil, playlist.canListTracks, let library = model.library else { return }
            tracks = PagedList(load: { try await library.playlistTracks(playlist, offset: $0) }, onError: model.handleLibraryError)
        }
    }

    private var header: some View {
        CollectionHeader(
            imageURL: playlist.coverURL ?? playlist.imageURL,
            title: playlist.name,
            subtitle: playlist.ownerName.map { "Playlist · \($0)" } ?? "Playlist",
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
                PagedListView(list: tracks) {
                    CollectionHeader(
                        imageURL: album.coverURL ?? album.imageURL,
                        title: album.name,
                        subtitle: album.artists.joined(separator: ", "),
                        play: { model.play(uri: album.uri, shuffled: false) },
                        shuffle: { model.play(uri: album.uri, shuffled: true) }
                    )
                } row: { index, track in
                    Button { model.play(tracks: tracks.items, startingAt: index) } label: { TrackRow(track: track, number: index + 1) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(album.name)
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
                PagedListView(list: tracks) {
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
            }
        }
        .navigationTitle(artist.name)
    }
}

/// Top of a playlist / album / artist page (and Liked Songs), like iOS Music:
/// a large cover, the title and a subtitle, then icon-only Liquid Glass
/// buttons — Play (prominent) and Shuffle.
struct CollectionHeader: View {
    let imageURL: URL?
    let title: String
    let subtitle: String
    var isCircular = false
    var canPlay = true
    let play: () -> Void
    let shuffle: () -> Void

    private static let coverSize: CGFloat = 140

    var body: some View {
        VStack(spacing: 6) {
            AsyncImage(url: imageURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Rectangle().fill(.white.opacity(0.08))
                    .overlay { Image(systemName: "music.note").font(.largeTitle).foregroundStyle(.white.opacity(0.3)) }
            }
            .frame(width: Self.coverSize, height: Self.coverSize)
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

            // Nearby glass buttons are grouped, so they render together.
            GlassEffectContainer {
                HStack(spacing: 16) {
                    // Same style as the player's play/pause button: smooth
                    // hover and press. Play is tinted with the accent color.
                    Button(action: play) { icon("play.fill") }
                        .buttonStyle(PlayButtonStyle(size: 52, tint: Theme.accent, tintOpacity: 0.45))
                        .accessibilityLabel("Play")
                    Button(action: shuffle) { icon("shuffle") }
                        .buttonStyle(PlayButtonStyle(size: 52))
                        .accessibilityLabel("Shuffle")
                }
                .foregroundStyle(.white)
                .disabled(!canPlay)
            }
            .padding(.top, 8)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .padding(.bottom, 10)
    }

    private func icon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.system(size: 20, weight: .semibold))
    }
}
