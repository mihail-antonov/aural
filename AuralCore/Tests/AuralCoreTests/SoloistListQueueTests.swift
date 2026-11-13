import Testing
@testable import AuralCore

struct SoloistListQueueTests {
    private let list = ["spotify:track:a", "spotify:track:b", "spotify:track:c", "spotify:track:d"]

    @Test func playsTheChosenTrackAndQueuesOnlyTheNextOne() throws {
        var queue = SoloistListQueue()
        let started = queue.start(list, at: 1)
        let step = try #require(started)
        #expect(step.play == "spotify:track:b")
        #expect(step.queue == "spotify:track:c")
        #expect(queue.trackStarted("spotify:track:b") == nil)
        // The queued track starts: queue the one after it.
        #expect(queue.trackStarted("spotify:track:c") == .addToQueue("spotify:track:d"))
        #expect(queue.trackStarted("spotify:track:d") == nil) // end of the list
    }

    @Test func skipsTracksQueuedForAnEarlierList() {
        var queue = SoloistListQueue()
        _ = queue.start(list, at: 0) // queues b
        _ = queue.start(["spotify:track:x", "spotify:track:y"], at: 0) // b is now stale
        #expect(queue.trackStarted("spotify:track:x") == nil)
        #expect(queue.trackStarted("spotify:track:b") == .skip)
        #expect(queue.trackStarted("spotify:track:y") == nil)
    }

    @Test func theChosenTrackIsNeverSkippedEvenIfAnOldCopyIsStale() {
        var queue = SoloistListQueue()
        _ = queue.start(list, at: 0) // queues b
        _ = queue.start(list, at: 1) // plays b; the queued b is stale
        #expect(queue.trackStarted("spotify:track:b") == nil)
        // The old copy of b still waiting in Soloist's queue is skipped when it starts.
        #expect(queue.trackStarted("spotify:track:b") == .skip)
    }

    @Test func previousRestartsTheListOneTrackBack() throws {
        var queue = SoloistListQueue()
        _ = queue.start(list, at: 1)
        _ = queue.trackStarted("spotify:track:b")
        #expect(queue.isPlaying("spotify:track:b"))
        let previous = queue.startPrevious()
        let step = try #require(previous)
        #expect(step.play == "spotify:track:a")
        #expect(step.queue == "spotify:track:b")
        #expect(queue.stale == ["spotify:track:c"])
    }

    @Test func playingSomethingElseMakesTheQueuedTrackStale() {
        var queue = SoloistListQueue()
        _ = queue.start(list, at: 0)
        queue.stop()
        #expect(!queue.isPlaying("spotify:track:a"))
        #expect(queue.trackStarted("spotify:track:b") == .skip)
    }

    @Test func upcomingIsTheRestOfTheListAndFollowsPlayback() {
        var queue = SoloistListQueue()
        _ = queue.start(list, at: 1)
        #expect(Array(queue.upcoming) == ["spotify:track:c", "spotify:track:d"])
        _ = queue.trackStarted("spotify:track:b")
        _ = queue.trackStarted("spotify:track:c")
        #expect(Array(queue.upcoming) == ["spotify:track:d"])
        _ = queue.start(["spotify:track:x"], at: 0)
        #expect(queue.upcoming.isEmpty)
        #expect(queue.isStale("spotify:track:d")) // was queued for the earlier list
    }

    @Test func clearedTracksAreSkippedWhenTheyStart() {
        var queue = SoloistListQueue()
        _ = queue.start(list, at: 0) // queues b
        _ = queue.trackStarted("spotify:track:a")
        queue.stop() // clear: b is stale
        queue.skipWhenStarted(["spotify:track:q"]) // a song the user queued
        #expect(queue.upcoming.isEmpty)
        #expect(queue.trackStarted("spotify:track:b") == .skip)
        #expect(queue.trackStarted("spotify:track:q") == .skip)
        #expect(queue.trackStarted("spotify:track:z") == nil)
    }
}
