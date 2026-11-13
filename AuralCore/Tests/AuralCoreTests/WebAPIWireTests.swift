import Foundation
import Testing
@testable import AuralCore

/// JSON shapes follow the Spotify Web API reference (Feb 2026 field names).
struct WebAPIWireTests {
    private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func playlistsPageMapsOwnershipAndCounts() throws {
        let paging: WebAPIWire.Paging<WebAPIWire.Playlist> = try decode("""
            {"items":[
              {"id":"p1","uri":"spotify:playlist:p1","name":"Mine","collaborative":false,
               "owner":{"id":"me","display_name":"Me"},"items":{"total":12},
               "images":[{"url":"https://img/640","width":640},{"url":"https://img/300","width":300},{"url":"https://img/60","width":60}]},
              {"id":"p2","uri":"spotify:playlist:p2","name":"Followed","collaborative":false,
               "owner":{"id":"someone"},"tracks":{"total":30},"images":[]},
              null
            ],"total":3,"offset":0,"next":"https://api.spotify.com/v1/me/playlists?offset=50"}
            """)
        let page = paging.page { PlaylistSummary(wire: $0, currentUserID: "me") }

        #expect(page.items.count == 2)
        #expect(page.nextOffset == 3)
        #expect(page.items[0].canListTracks)
        #expect(page.items[0].isOwnedByUser)
        #expect(page.items[0].trackCount == 12)
        #expect(page.items[0].imageURL == URL(string: "https://img/60")) // 60 px is enough for a 72 px thumbnail
        #expect(!page.items[1].canListTracks)
        #expect(!page.items[1].isOwnedByUser)
        #expect(page.items[1].trackCount == 30) // old `tracks` field still read
        #expect(page.items[1].imageURL == nil)
    }

    @Test func playlistItemsSkipEpisodesLocalFilesAndNulls() throws {
        let paging: WebAPIWire.Paging<WebAPIWire.PlaylistItem> = try decode("""
            {"items":[
              {"item":{"id":"t1","uri":"spotify:track:t1","name":"Song","type":"track","duration_ms":1000,
                       "artists":[{"name":"A"},{"name":"B"}],"album":{"id":"a","uri":"spotify:album:a","name":"Album"}}},
              {"item":{"id":"e1","uri":"spotify:episode:e1","name":"Episode","type":"episode"}},
              {"item":{"id":null,"uri":"spotify:local:x","name":"Local","type":"track","is_local":true}},
              {"item":null}
            ],"total":4,"offset":0,"next":null}
            """)
        let page = paging.page { ($0.item ?? $0.track).flatMap { TrackSummary(wire: $0) } }

        #expect(page.items.map(\.id) == ["t1"])
        #expect(page.items[0].artists == ["A", "B"])
        #expect(page.items[0].album == "Album")
        #expect(page.nextOffset == nil)
    }

    @Test func thumbnailSkipsImagesThatAreTooSmall() {
        let images = [WebAPIWire.Image(url: "https://img/640", width: 640), WebAPIWire.Image(url: "https://img/32", width: 32),
                      WebAPIWire.Image(url: "https://img/160", width: 160)]
        #expect(WebAPIWire.imageURL(images) == URL(string: "https://img/160"))
        #expect(WebAPIWire.imageURL([WebAPIWire.Image(url: "https://img/x", width: nil)]) == URL(string: "https://img/x"))
    }

    @Test func albumTracksUseTheAlbumsArtwork() throws {
        let album = AlbumSummary(id: "a", uri: "spotify:album:a", name: "Album", artists: ["X"], imageURL: URL(string: "https://img/a"), trackCount: 1)
        let track: WebAPIWire.Track = try decode(#"{"id":"t","uri":"spotify:track:t","name":"T","duration_ms":5,"artists":[{"name":"X"}]}"#)
        let summary = try #require(TrackSummary(wire: track, albumFallback: album))
        #expect(summary.imageURL == URL(string: "https://img/a"))
        #expect(summary.album == "Album")
    }

    @Test func soloistQueueCommandEncodesURI() throws {
        let data = try JSONEncoder().encode(SoloistCommand.addToQueue(uri: "spotify:track:t"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(json == ["type": "command", "command": "add_to_queue", "uri": "spotify:track:t"])
    }
}
