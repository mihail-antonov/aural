import Foundation

// Small, source-independent library models. Web API responses are decoded
// into wire types and mapped to these right away; full JSON is never kept.

public struct PlaylistSummary: Sendable, Identifiable, Hashable {
    public let id: String
    public let uri: String
    public let name: String
    public let ownerName: String?
    /// Small image for list rows (~64 px).
    public let imageURL: URL?
    /// Larger image for the playlist's page header (~300 px).
    public let coverURL: URL?
    public let trackCount: Int?
    /// The user's own playlist. It is always in their library, so Aural
    /// offers no "save" / "remove" for it (removing would delete it).
    public let isOwnedByUser: Bool
    /// Spotify only returns the tracks of playlists the user owns or
    /// collaborates on. Others can be played, but their tracks are not listed.
    public let canListTracks: Bool
}

public struct AlbumSummary: Sendable, Identifiable, Hashable {
    public let id: String
    public let uri: String
    public let name: String
    public let artists: [String]
    /// Small image for list rows (~64 px).
    public let imageURL: URL?
    /// Larger image for the album's page header (~300 px).
    public let coverURL: URL?
    public let trackCount: Int?

    public init(id: String, uri: String, name: String, artists: [String], imageURL: URL?, coverURL: URL? = nil, trackCount: Int?) {
        self.id = id
        self.uri = uri
        self.name = name
        self.artists = artists
        self.imageURL = imageURL
        self.coverURL = coverURL
        self.trackCount = trackCount
    }
}

public struct ArtistSummary: Sendable, Identifiable, Hashable {
    public let id: String
    public let uri: String
    public let name: String
    public let imageURL: URL?
}

public struct TrackSummary: Sendable, Identifiable, Hashable {
    public let id: String
    public let uri: String
    public let title: String
    public let artists: [String]
    public let album: String?
    /// Small image for list rows (~64 px).
    public let imageURL: URL?
    /// Larger album image (~300 px), for the Liked Songs header.
    public let coverURL: URL?
    public let durationMs: Int
}

/// One page of a paginated list. `nextOffset` is nil on the last page.
public struct Page<Item: Sendable>: Sendable {
    public let items: [Item]
    public let total: Int
    public let nextOffset: Int?

    public static var empty: Page { Page(items: [], total: 0, nextOffset: nil) }
}

public struct SearchResults: Sendable {
    public let tracks: [TrackSummary]
    public let albums: [AlbumSummary]
    public let artists: [ArtistSummary]
    public let playlists: [PlaylistSummary]

    public static let empty = SearchResults(tracks: [], albums: [], artists: [], playlists: [])
    public var isEmpty: Bool { tracks.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty }
}
