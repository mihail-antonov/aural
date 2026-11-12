import Testing
@testable import AuralCore

struct SoloistHistoryTests {
    private func queued(_ uris: String...) -> [SoloistWire.QueueEntry] {
        uris.map { .init(source: "queue", item: .init(uri: $0)) }
    }

    @Test func goesBackToThePreviouslyPlayedTrackAndRequeuesTheRest() {
        var history = SoloistHistory()
        for uri in ["spotify:track:a", "spotify:track:b", "spotify:track:c"] { history.trackStarted(uri) }
        _ = history.tracksToRequeue(upcoming: queued("spotify:track:d"), currentURI: "spotify:track:c")

        let action = history.previous(currentURI: "spotify:track:c", positionMs: 1_000, contextType: "track")
        #expect(action == .play(uri: "spotify:track:b"))

        // Soloist switched and cleared its queue: queue the track we left and the rest again.
        history.trackStarted("spotify:track:b")
        #expect(history.tracksToRequeue(upcoming: [], currentURI: "spotify:track:b") == ["spotify:track:c", "spotify:track:d"])
        #expect(history.played == ["spotify:track:a", "spotify:track:b"])
    }

    @Test func doesNotRequeueWhenSoloistKeptItsQueue() {
        var history = SoloistHistory()
        history.trackStarted("spotify:track:a")
        history.trackStarted("spotify:track:b")
        _ = history.previous(currentURI: "spotify:track:b", positionMs: 0, contextType: nil)
        history.trackStarted("spotify:track:a")
        #expect(history.tracksToRequeue(upcoming: queued("spotify:track:x"), currentURI: "spotify:track:a").isEmpty)
    }

    @Test func restartsAfterThreeSecondsOrWithoutHistory() {
        var history = SoloistHistory()
        history.trackStarted("spotify:track:a")
        #expect(history.previous(currentURI: "spotify:track:a", positionMs: 0, contextType: "track") == .restart)
        history.trackStarted("spotify:track:b")
        #expect(history.previous(currentURI: "spotify:track:b", positionMs: 5_000, contextType: "track") == .restart)
    }

    @Test func playlistsAndAlbumsUseSoloistsOwnPrevious() {
        var history = SoloistHistory()
        history.trackStarted("spotify:track:a")
        history.trackStarted("spotify:track:b")
        #expect(history.previous(currentURI: "spotify:track:b", positionMs: 0, contextType: "album") == .skipInContext)
    }

    @Test func historyIsBounded() {
        var history = SoloistHistory()
        for index in 0..<(SoloistHistory.capacity + 10) { history.trackStarted("spotify:track:\(index)") }
        #expect(history.played.count == SoloistHistory.capacity)
    }
}
