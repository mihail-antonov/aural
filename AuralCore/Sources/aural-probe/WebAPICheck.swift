import AppKit
import AuralCore
import Foundation

/// `aural-probe webapi-check --client-id ID`
///
/// Signs in through the browser (tokens stay in memory only) and calls every
/// Web API endpoint Aural plans to use, printing status codes and counts —
/// never names or other library contents. Like/unlike is tested on a search
/// result that is not liked yet, and undone right away.
enum WebAPICheck {
    // Minimal shapes: only what the check needs.
    struct Me: Decodable, Sendable { let id: String }
    struct Page<Item: Decodable & Sendable>: Decodable, Sendable { let items: [Item]; let total: Int; let next: String? }
    struct Owner: Decodable, Sendable { let id: String }
    struct Playlist: Decodable, Sendable { let id: String; let owner: Owner; let collaborative: Bool }
    struct SavedAlbum: Decodable, Sendable { struct Album: Decodable, Sendable { let id: String }; let album: Album }
    struct Track: Decodable, Sendable { let uri: String }
    struct SearchResult: Decodable, Sendable {
        struct Section: Decodable, Sendable { let total: Int; let items: [Optional<Track>]? }
        struct Other: Decodable, Sendable { let total: Int }
        let tracks: Section?
        let albums: Other?
        let artists: Other?
        let playlists: Other?
    }

    static func run(clientID: String, say: (String) -> Void) async {
        let auth = SpotifyAuth(clientID: clientID)
        say("Opening the browser to sign in to Spotify (redirect \(SpotifyAuth.redirectURI))…")
        let tokens: SpotifyTokens
        do {
            tokens = try await auth.login { url in
                await MainActor.run { _ = NSWorkspace.shared.open(url) }
            }
        } catch {
            say("login failed: \(error.localizedDescription)")
            return
        }
        say("signed in; granted scopes: \(tokens.scope)")
        let api = WebAPIClient(auth: auth, tokens: tokens)

        func check<T: Decodable & Sendable>(_ label: String, _ path: String, _ query: [URLQueryItem] = [], as type: T.Type) async -> T? {
            do {
                let value = try await api.get(path, query: query, as: T.self)
                say("200  \(label)")
                return value
            } catch {
                say("ERR  \(label): \(error.localizedDescription)")
                return nil
            }
        }
        let limit50 = [URLQueryItem(name: "limit", value: "50")]

        let me = await check("GET /me", "me", as: Me.self)

        if let playlists = await check("GET /me/playlists?limit=50", "me/playlists", limit50, as: Page<Playlist>.self) {
            let mine = playlists.items.filter { $0.owner.id == me?.id || $0.collaborative }
            let others = playlists.items.filter { !($0.owner.id == me?.id || $0.collaborative) }
            say("     playlists: total \(playlists.total), on first page \(playlists.items.count) (own/collaborative \(mine.count), followed \(others.count)), more pages: \(playlists.next != nil)")
            if let own = mine.first {
                say("\(await api.status("GET", "playlists/\(own.id)/items", query: [URLQueryItem(name: "limit", value: "50")]))  GET /playlists/{own}/items")
            }
            if let followed = others.first {
                say("\(await api.status("GET", "playlists/\(followed.id)/items", query: [URLQueryItem(name: "limit", value: "50")]))  GET /playlists/{followed}/items  (403 expected)")
            }
        }

        if let saved = await check("GET /me/tracks?limit=50", "me/tracks", limit50, as: Page<IgnoredItem>.self) {
            say("     liked songs: total \(saved.total)")
        }
        if let albums = await check("GET /me/albums?limit=50", "me/albums", limit50, as: Page<SavedAlbum>.self) {
            say("     saved albums: total \(albums.total)")
            if let album = albums.items.first {
                say("\(await api.status("GET", "albums/\(album.album.id)/tracks", query: limit50))  GET /albums/{id}/tracks?limit=50")
            }
        }

        let searchQuery = [
            URLQueryItem(name: "q", value: "piano"),
            URLQueryItem(name: "type", value: "track,album,artist,playlist"),
            URLQueryItem(name: "limit", value: "10"),
        ]
        let search = await check("GET /search?type=track,album,artist,playlist&limit=10", "search", searchQuery, as: SearchResult.self)
        if let search {
            say("     search counts on page: tracks \(search.tracks?.items?.count ?? 0)")
        }
        let overLimit = [URLQueryItem(name: "q", value: "piano"), URLQueryItem(name: "type", value: "track"), URLQueryItem(name: "limit", value: "11")]
        say("\(await api.status("GET", "search", query: overLimit))  GET /search?limit=11  (400 expected: max is 10)")

        // Like / unlike on a track that is not liked yet, restored afterwards.
        let candidates = (search?.tracks?.items ?? []).compactMap { $0?.uri }
        await checkLibrary(api: api, candidates: candidates, say: say)

        if let me {
            say("     Liked Songs context URI to try with Soloist: spotify:user:\(me.id):collection")
        }
    }

    private static func checkLibrary(api: WebAPIClient, candidates: [String], say: (String) -> Void) async {
        func contains(_ uri: String) async -> Bool? {
            do {
                let result = try await api.get("me/library/contains", query: [URLQueryItem(name: "uris", value: uri)], as: [Bool].self)
                return result.first
            } catch {
                say("ERR  GET /me/library/contains: \(error.localizedDescription)")
                return nil
            }
        }
        guard let first = candidates.first, let firstSaved = await contains(first) else { return }
        say("200  GET /me/library/contains  → [\(firstSaved)]")

        var target: String?
        for uri in candidates where await contains(uri) == false {
            target = uri
            break
        }
        guard let target else {
            say("     skipped like/unlike: every candidate is already liked")
            return
        }
        let uris = [URLQueryItem(name: "uris", value: target)]
        say("\(await api.status("PUT", "me/library", query: uris))  PUT /me/library (like)")
        say("     contains after like: \(String(describing: await contains(target)))")
        say("\(await api.status("DELETE", "me/library", query: uris))  DELETE /me/library (unlike, restores the original state)")
        say("     contains after unlike: \(String(describing: await contains(target)))")
    }

    /// Decodes any JSON value and keeps nothing.
    struct IgnoredItem: Decodable, Sendable {
        init(from decoder: any Decoder) throws {}
    }
}
