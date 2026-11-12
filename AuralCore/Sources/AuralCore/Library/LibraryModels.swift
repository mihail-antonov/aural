import Foundation

// Small, source-independent library models. Web API responses are decoded
// into wire types and mapped to these right away; full JSON is never kept.

public struct PlaylistSummary: Sendable, Identifiable, Hashable {
    public let id: String
    public let uri: String
    public let name: String
    public let ownerName: String?
    public let imageURL: URL?
    public let trackCount: Int?
    /// Spotify only returns the tracks of playlists the user owns or
    /// collaborates on. Others can be played, but their tracks are not listed.
    public let canListTracks: Bool
}

public struct AlbumSummary: Sendable, Identifiable, Hashable {
    public let id: String
    public let uri: String
    public let name: String
    public let artists: [String]
    public let imageURL: URL?
    public let trackCount: Int?
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
    public let imageURL: URL?
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
