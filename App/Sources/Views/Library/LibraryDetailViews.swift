import AuralCore
import SwiftUI

struct PlaylistDetailView: View {
    let playlist: PlaylistSummary
    let model: AppModel
    @State private var tracks: PagedList<TrackSummary>?

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: playlist.name, subtitle: playlist.ownerName, imageURL: playlist.imageURL) {
                model.play(uri: playlist.uri)
            }
            if let tracks {
                PagedListView(list: tracks) { index, track in
                    Button { model.play(tracks: tracks.items, startingAt: index) } label: { TrackRow(track: track) }
                        .buttonStyle(.plain)
                }
            } else {
                ContentUnavailableView(
                    "Tracks not available",
                    systemImage: "lock",
                    description: Text("Spotify only shares the tracks of playlists you own or collaborate on. You can still play this playlist.")
                )
            }
        }
        .navigationTitle(playlist.name)
        .task {
            guard tracks == nil, playlist.canListTracks, let library = model.library else { return }
            tracks = PagedList(load: { try await library.playlistTracks(playlist, offset: $0) }, onError: model.handleLibraryError)
        }
    }
}

struct AlbumDetailView: View {
    let album: AlbumSummary
    let model: AppModel
    @State private var tracks: PagedList<TrackSummary>?

    var body: some View {
        VStack(spacing: 0) {
            DetailHeader(title: album.name, subtitle: album.artists.joined(separator: ", "), imageURL: album.imageURL) {
                model.play(uri: album.uri)
            }
            if let tracks {
                PagedListView(list: tracks) { index, track in
                    Button { model.play(tracks: tracks.items, startingAt: index) } label: { TrackRow(track: track, number: index + 1) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(album.name)
        .task {
            guard tracks == nil, let library = model.library else { return }
            tracks = PagedList(load: { try await library.albumTracks(album, offset: $0) }, onError: model.handleLibraryError)
        }
    }
}

/// Soloist cannot play an artist, so the artist page lists their tracks (from search).
struct ArtistDetailView: View {
    let artist: ArtistSummary
    let model: AppModel
    @State private var tracks: PagedList<TrackSummary>?

    var body: some View {
        VStack(spacing: 0) {
            if let tracks {
                PagedListView(list: tracks) { index, track in
                    Button { model.play(tracks: tracks.items, startingAt: index) } label: { TrackRow(track: track) }
                        .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(artist.name)
        .task {
            guard tracks == nil, let library = model.library else { return }
            tracks = PagedList(load: { try await library.tracks(by: artist, offset: $0) }, onError: model.handleLibraryError)
        }
    }
}

private struct DetailHeader: View {
    let title: String
    let subtitle: String?
    let imageURL: URL?
    let play: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Thumbnail(url: imageURL, size: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline).lineLimit(2)
                if let subtitle { Text(subtitle).foregroundStyle(.secondary).lineLimit(1) }
            }
            Spacer()
            Button("Play", systemImage: "play.fill", action: play)
                .buttonStyle(.borderedProminent)
        }
        .padding(12)
    }
}
