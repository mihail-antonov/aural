import Foundation

// Decodable mirrors of Spotify Web API JSON (only the fields Aural uses) and
// their mapping to the library models. Optional fields are lenient on purpose:
// playlists can contain episodes, local files or null entries.

enum WebAPIWire {
    struct Image: Decodable, Sendable { let url: String; let width: Int? }

    struct Artist: Decodable, Sendable {
        let id: String?
        let uri: String?
        let name: String
        let images: [Image]?
    }

    struct Album: Decodable, Sendable {
        let id: String
        let uri: String
        let name: String
        let images: [Image]?
        let artists: [Artist]?
        let totalTracks: Int?
        enum CodingKeys: String, CodingKey { case id, uri, name, images, artists; case totalTracks = "total_tracks" }
    }

    struct Track: Decodable, Sendable {
        let id: String?
        let uri: String?
        let name: String?
        let type: String?
        let artists: [Artist]?
        let album: Album?
        let durationMs: Int?
        let isLocal: Bool?
        enum CodingKeys: String, CodingKey {
            case id, uri, name, type, artists, album
            case durationMs = "duration_ms"
            case isLocal = "is_local"
        }
    }

    struct Owner: Decodable, Sendable {
        let id: String
        let displayName: String?
        enum CodingKeys: String, CodingKey { case id; case displayName = "display_name" }
    }

    struct Count: Decodable, Sendable { let total: Int? }

    struct Playlist: Decodable, Sendable {
        let id: String
        let uri: String
        let name: String
        let images: [Image]?
        let owner: Owner?
        let collaborative: Bool?
        /// Feb 2026: `tracks` was renamed to `items`; read either.
        let items: Count?
        let tracks: Count?
    }

    struct Paging<Item: Decodable & Sendable>: Decodable, Sendable {
        /// Entries can be `null` (e.g. removed playlists in search results).
        let items: [Item?]
        let total: Int
        let offset: Int?
        let next: String?
    }

    struct PlaylistItem: Decodable, Sendable {
        /// Feb 2026: `track` was renamed to `item`; read either.
        let item: Track?
        let track: Track?
    }

    struct SavedTrack: Decodable, Sendable { let track: Track? }
    struct SavedAlbum: Decodable, Sendable { let album: Album? }
    struct Me: Decodable, Sendable { let id: String }

    struct Search: Decodable, Sendable {
        let tracks: Paging<Track>?
        let albums: Paging<Album>?
        let artists: Paging<Artist>?
        let playlists: Paging<Playlist>?
    }
}

// MARK: - Mapping

extension WebAPIWire.Paging {
    func page<Mapped>(_ transform: (Item) -> Mapped?) -> Page<Mapped> {
        let start = offset ?? 0
        return Page(
            items: items.compactMap { $0.flatMap(transform) },
            total: total,
            nextOffset: next == nil ? nil : start + items.count
        )
    }
}

extension WebAPIWire {
    /// Thumbnail URL: the smallest image that is at least ~80% of
    /// `targetWidth` px. Rows show 36 pt (72 px on Retina), so the default
    /// accepts Spotify's 60 / 64 px variants instead of jumping to 300 px —
    /// a 300 px image decodes to ~350 KB, a 64 px one to ~16 KB.
    /// Images without a known width count as large.
    static func imageURL(_ images: [Image]?, targetWidth: Int = 72) -> URL? {
        guard let images, !images.isEmpty else { return nil }
        let sorted = images.sorted { ($0.width ?? .max) < ($1.width ?? .max) }
        let minimum = targetWidth * 4 / 5
        let image = sorted.first { ($0.width ?? .max) >= minimum } ?? sorted.last
        return image.flatMap { URL(string: $0.url) }
    }

    /// Image for a page header (shown at ~140 pt, 280 px on Retina).
    static func coverURL(_ images: [Image]?) -> URL? {
        imageURL(images, targetWidth: 280)
    }
}

extension TrackSummary {
    /// Nil for episodes, local files and entries without a playable URI.
    init?(wire track: WebAPIWire.Track, albumFallback: AlbumSummary? = nil) {
        guard track.type == nil || track.type == "track", track.isLocal != true,
              let id = track.id, let uri = track.uri, let title = track.name
        else { return nil }
        self.init(
            id: id,
            uri: uri,
            title: title,
            artists: (track.artists ?? []).map(\.name),
            album: track.album?.name ?? albumFallback?.name,
            imageURL: WebAPIWire.imageURL(track.album?.images) ?? albumFallback?.imageURL,
            coverURL: WebAPIWire.coverURL(track.album?.images) ?? albumFallback?.coverURL,
            durationMs: track.durationMs ?? 0
        )
    }
}

extension AlbumSummary {
    init(wire album: WebAPIWire.Album) {
        self.init(
            id: album.id,
            uri: album.uri,
            name: album.name,
            artists: (album.artists ?? []).map(\.name),
            imageURL: WebAPIWire.imageURL(album.images),
            coverURL: WebAPIWire.coverURL(album.images),
            trackCount: album.totalTracks
        )
    }
}

extension ArtistSummary {
    init?(wire artist: WebAPIWire.Artist) {
        guard let id = artist.id, let uri = artist.uri else { return nil }
        self.init(id: id, uri: uri, name: artist.name, imageURL: WebAPIWire.imageURL(artist.images))
    }
}

extension PlaylistSummary {
    init(wire playlist: WebAPIWire.Playlist, currentUserID: String?) {
        let isOwn = playlist.owner?.id != nil && playlist.owner?.id == currentUserID
        self.init(
            id: playlist.id,
            uri: playlist.uri,
            name: playlist.name,
            ownerName: playlist.owner?.displayName,
            imageURL: WebAPIWire.imageURL(playlist.images),
            coverURL: WebAPIWire.coverURL(playlist.images),
            trackCount: playlist.items?.total ?? playlist.tracks?.total,
            isOwnedByUser: isOwn,
            canListTracks: isOwn || playlist.collaborative == true
        )
    }
}
