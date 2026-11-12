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
        #expect(track.artworkURL == URL(string: "https://example.com/cover-default.jpg"))
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
        #expect(state.applying(.queueChanged) == state)
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
