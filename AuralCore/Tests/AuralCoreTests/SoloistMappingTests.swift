import CoreGraphics
import Foundation
import Testing
@testable import AuralCore

struct SoloistMappingTests {
    private func snapshot() throws -> PlaybackState {
        let url = try #require(Bundle.module.url(forResource: "playback_state", withExtension: "json", subdirectory: "Fixtures"))
        let event = try SoloistEvent.decode(from: Data(contentsOf: url))
        return PlaybackState().applying(event)
    }

    @Test func snapshotMapsToPlaybackState() throws {
        let state = try snapshot()
        #expect(state.status == .playing)
        #expect(state.volume == 40)
        #expect(state.isActiveDevice)
        #expect(state.shuffle == false)
        #expect(state.repeatMode == .context)
        // seek_forward / seek_backward are not Aural actions; shuffle/set_repeat absent here.
        #expect(state.availableActions == [.addToQueue, .pause, .seek, .skipNext, .skipPrevious])

        let track = try #require(state.track)
        #expect(track.id == "spotify:track:0000000000000000000001")
        #expect(track.title == "Test Track")
        #expect(track.artists == ["First Artist", "Second Artist"])
        #expect(track.album == "Test Album")
        #expect(track.durationMs == 194768)
        #expect(track.artworkURL == URL(string: "https://example.com/cover-large.jpg"))
    }

    @Test func partialEventsUpdateOnlyTheirField() throws {
        let state = try snapshot()
            .applying(.playbackChanged(status: "paused"))
            .applying(.volumeChanged(25))
            .applying(.optionsChanged(.init(shuffle: true, repeat: "track")))

        #expect(state.status == .paused)
        #expect(state.volume == 25)
        #expect(state.shuffle)
        #expect(state.repeatMode == .track)
        #expect(state.track?.title == "Test Track")
    }

    @Test func eventsWithoutStateChangeLeaveStateUntouched() throws {
        let state = try snapshot()
        #expect(state.applying(.queueChanged(upcoming: [])) == state)
        #expect(state.applying(.commandResult(command: "pause")) == state)
        #expect(state.applying(.unknown(type: "x")) == state)
    }

    @Test func unknownStatusFallsBackToIdle() throws {
        #expect(try snapshot().applying(.playbackChanged(status: "teleporting")).status == .idle)
    }

    @Test func placeholderEntitiesAreNotTracks() {
        let placeholder = SoloistWire.Entity(uri: "", entityType: "unknown", decorations: nil)
        #expect(PlaybackState().applying(.trackChanged(placeholder)).track == nil)
    }

    @Test func positionIsComputedFromTheAnchor() {
        let anchor = Date(timeIntervalSince1970: 1_000)
        let playing = PlaybackPosition(positionMs: 10_000, timestamp: anchor, speed: 1)
        #expect(playing.current(at: anchor.addingTimeInterval(2.5)) == 12_500)
        #expect(playing.current(at: anchor.addingTimeInterval(100), durationMs: 60_000) == 60_000)

        let paused = PlaybackPosition(positionMs: 10_000, timestamp: anchor, speed: 0)
        #expect(paused.current(at: anchor.addingTimeInterval(30)) == 10_000)
    }

    @Test func positionSyncUsesSoloistTimestamp() {
        let state = PlaybackState().applying(.positionSync(.init(positionMs: 5_000, timestampMs: 1_000_000, speed: 1)))
        #expect(state.position.positionMs == 5_000)
        #expect(state.position.timestamp == Date(timeIntervalSince1970: 1_000))
    }
}

struct ContextAndColorTests {
    @Test func contextNameComesFromPlaylistOrAlbumContext() throws {
        let event = try SoloistEvent.decode(from: Data(#"{"type":"context_changed","context":{"uri":"spotify:playlist:p","entity_type":"playlist","decorations":{"identity":{"name":"Road Trip"}}}}"#.utf8))
        #expect(PlaybackState().applying(event).contextName == "Road Trip")

        let single = try SoloistEvent.decode(from: Data(#"{"type":"context_changed","context":{"uri":"spotify:track:t","entity_type":"track","decorations":{}}}"#.utf8))
        #expect(PlaybackState().applying(event).applying(single).contextName == nil)
    }

    @Test func averageColorOfASolidImage() throws {
        let context = try #require(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(red: 1, green: 0.5, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        let color = try #require(ArtworkLoader.averageColor(of: image))
        #expect(abs(color.red - 1) < 0.02 && abs(color.green - 0.5) < 0.02 && color.blue < 0.02)
    }

    @Test func queueEntriesKeepTracksWithDetailsAndTheirSource() throws {
        let event = try SoloistEvent.decode(from: Data(#"""
            {"type":"queue_changed","upcoming":[
              {"uid":"q1","source":"context","item":{"uri":"spotify:track:a","entity_type":"track","decorations":{
                "identity":{"name":"Song A"},
                "visual_identity":{"cover":[{"url":"https://img/small","size":"small"},{"url":"https://img/large","size":"large"}]},
                "creators":[{"entity":{"uri":"spotify:artist:x","decorations":{"identity":{"name":"Artist"}}}}],
                "playback":{"duration_ms":1000}}}},
              {"source":"autoplay","item":{"uri":"spotify:track:b","entity_type":"track","decorations":{"identity":{"name":"Song B"}}}},
              {"uid":"p","source":"context","item":{"uri":"spotify:meta:node_rules_placeholder","entity_type":"unknown"}}
            ]}
            """#.utf8))
        guard case .queueChanged(let upcoming) = event else { Issue.record("not a queue event"); return }
        let entries = QueueEntry.entries(soloist: upcoming)

        #expect(entries.map(\.track.title) == ["Song A", "Song B"])
        #expect(entries.map(\.source) == [.context, .autoplay])
        #expect(entries[0].id == "q1")
        #expect(entries[0].track.artists == ["Artist"])
        #expect(entries[0].track.thumbnailURL == URL(string: "https://img/small"))
        #expect(entries[0].track.artworkURL == URL(string: "https://img/large"))
        #expect(entries[1].id == "1-spotify:track:b") // no uid: position and URI
    }
}
