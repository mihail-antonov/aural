import AuralCore
import SwiftUI

struct TrackRow: View {
    let track: TrackSummary
    var showsArtwork = true

    var body: some View {
        HStack(spacing: 10) {
            if showsArtwork { Thumbnail(url: track.imageURL, size: 36) }
            VStack(alignment: .leading, spacing: 1) {
                Text(track.title).lineLimit(1)
                Text(track.artists.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(.rect) // the whole row is clickable, not only the text
    }
}

struct PlaylistRow: View {
    let playlist: PlaylistSummary

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(url: playlist.imageURL, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(playlist.name).lineLimit(1)
                Text([playlist.ownerName, playlist.trackCount.map { "\($0) tracks" }].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct AlbumRow: View {
    let album: AlbumSummary

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(url: album.imageURL, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(album.name).lineLimit(1)
                Text(album.artists.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct ArtistRow: View {
    let artist: ArtistSummary

    var body: some View {
        HStack(spacing: 10) {
            Thumbnail(url: artist.imageURL, size: 36, circular: true)
            Text(artist.name).lineLimit(1)
        }
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
            Rectangle().fill(.quaternary)
        }
        .frame(width: size, height: size)
        .clipShape(circular ? AnyShape(.circle) : AnyShape(.rect(cornerRadius: 4)))
    }
}
