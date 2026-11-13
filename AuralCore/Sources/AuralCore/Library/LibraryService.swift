import Foundation

/// The user's Spotify library and search, through the Web API.
/// Every endpoint used here was confirmed with a real request in Stage 3
/// (see "Progress" in CLAUDE.md).
public actor LibraryService {
    /// Max page size of the library endpoints. Search allows at most 10.
    public static let pageSize = 50
    public static let searchPageSize = 10

    private let api: WebAPIClient
    private var currentUserID: String?

    public init(api: WebAPIClient) {
        self.api = api
    }

    public enum LibraryError: Error, Equatable {
        /// Spotify does not return the tracks of followed playlists (403).
        case playlistTracksUnavailable
    }

    // MARK: - Lists

    public func playlists(offset: Int = 0) async throws(WebAPIError) -> Page<PlaylistSummary> {
        let userID = try await userID()
        let paging: WebAPIWire.Paging<WebAPIWire.Playlist> = try await api.get("me/playlists", query: Self.paging(offset))
        return paging.page { PlaylistSummary(wire: $0, currentUserID: userID) }
    }

    public func playlistTracks(_ playlist: PlaylistSummary, offset: Int = 0) async throws -> Page<TrackSummary> {
        guard playlist.canListTracks else { throw LibraryError.playlistTracksUnavailable }
        do {
            let paging: WebAPIWire.Paging<WebAPIWire.PlaylistItem> = try await api.get(
                "playlists/\(playlist.id)/items",
                query: Self.paging(offset) + [URLQueryItem(name: "additional_types", value: "track")]
            )
            return paging.page { ($0.item ?? $0.track).flatMap { TrackSummary(wire: $0) } }
        } catch .forbidden {
            throw LibraryError.playlistTracksUnavailable
        }
    }

    public func likedSongs(offset: Int = 0) async throws(WebAPIError) -> Page<TrackSummary> {
        let paging: WebAPIWire.Paging<WebAPIWire.SavedTrack> = try await api.get("me/tracks", query: Self.paging(offset))
        return paging.page { $0.track.flatMap { TrackSummary(wire: $0) } }
    }

    public func savedAlbums(offset: Int = 0) async throws(WebAPIError) -> Page<AlbumSummary> {
        let paging: WebAPIWire.Paging<WebAPIWire.SavedAlbum> = try await api.get("me/albums", query: Self.paging(offset))
        return paging.page { $0.album.map(AlbumSummary.init(wire:)) }
    }

    public func albumTracks(_ album: AlbumSummary, offset: Int = 0) async throws(WebAPIError) -> Page<TrackSummary> {
        let paging: WebAPIWire.Paging<WebAPIWire.Track> = try await api.get("albums/\(album.id)/tracks", query: Self.paging(offset))
        // Album track objects have no album or images; reuse the album's.
        return paging.page { TrackSummary(wire: $0, albumFallback: album) }
    }

    // MARK: - Search

    /// First 10 results of each type (Spotify's maximum per request).
    public func search(_ text: String) async throws(WebAPIError) -> SearchResults {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return .empty }
        let userID = try await userID()
        let result: WebAPIWire.Search = try await api.get("search", query: [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track,album,artist,playlist"),
            URLQueryItem(name: "limit", value: String(Self.searchPageSize)),
        ])
        return SearchResults(
            tracks: result.tracks?.page { TrackSummary(wire: $0) }.items ?? [],
            albums: result.albums?.page(AlbumSummary.init(wire:)).items ?? [],
            artists: result.artists?.page(ArtistSummary.init(wire:)).items ?? [],
            playlists: result.playlists?.page { PlaylistSummary(wire: $0, currentUserID: userID) }.items ?? []
        )
    }

    /// Soloist cannot play artist URIs, so an artist shows its tracks from search.
    public func tracks(by artist: ArtistSummary, offset: Int = 0) async throws(WebAPIError) -> Page<TrackSummary> {
        let paging: WebAPIWire.Search = try await api.get("search", query: [
            URLQueryItem(name: "q", value: "artist:\"\(artist.name)\""),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: String(Self.searchPageSize)),
            URLQueryItem(name: "offset", value: String(offset)),
        ])
        return paging.tracks?.page { TrackSummary(wire: $0) } ?? .empty
    }

    // MARK: - Saved items (Liked Songs, saved albums and playlists)

    /// Whether the item is in the user's library: a track in Liked Songs, a
    /// saved album or a saved (followed) playlist. Takes any of those URIs.
    public func isSaved(_ uri: String) async throws(WebAPIError) -> Bool {
        let result: [Bool] = try await api.get("me/library/contains", query: [URLQueryItem(name: "uris", value: uri)])
        return result.first ?? false
    }

    /// Saves or removes a track (Liked Songs), album or playlist. Saving a
    /// playlist may need a scope Aural does not request; Spotify then
    /// answers 403 (`.forbidden`).
    public func setSaved(_ saved: Bool, uri: String) async throws(WebAPIError) {
        try await api.send(saved ? "PUT" : "DELETE", "me/library", query: [URLQueryItem(name: "uris", value: uri)])
    }

    // MARK: - Helpers

    private func userID() async throws(WebAPIError) -> String {
        if let currentUserID { return currentUserID }
        let me: WebAPIWire.Me = try await api.get("me")
        currentUserID = me.id
        return me.id
    }

    private static func paging(_ offset: Int) -> [URLQueryItem] {
        [URLQueryItem(name: "limit", value: String(pageSize)), URLQueryItem(name: "offset", value: String(offset))]
    }
}

/// The Client ID and tokens, stored together as one Keychain item.
public struct WebAPICredentials: Codable, Sendable, Equatable {
    public let clientID: String
    public var tokens: SpotifyTokens

    public init(clientID: String, tokens: SpotifyTokens) {
        self.clientID = clientID
        self.tokens = tokens
    }

    public static let keychainService = "app.aural.spotify-web-api"

    public static func load() -> WebAPICredentials? {
        guard let json = try? Keychain.readPassword(service: keychainService) else { return nil }
        return try? JSONDecoder().decode(WebAPICredentials.self, from: Data(json.utf8))
    }

    public func save() throws(KeychainError) {
        // Encoding a struct of strings and a date cannot fail.
        let data = (try? JSONEncoder().encode(self)) ?? Data()
        try Keychain.savePassword(String(decoding: data, as: UTF8.self), service: Self.keychainService)
    }

    public static func delete() throws(KeychainError) {
        try Keychain.deletePassword(service: keychainService)
    }
}
