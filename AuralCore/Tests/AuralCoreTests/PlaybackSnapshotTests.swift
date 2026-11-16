import Foundation
import Testing
@testable import AuralCore

struct PlaybackSnapshotTests {
    private func track(_ id: String) -> Track {
        Track(id: "spotify:track:\(id)", title: id, artists: ["Artist"], album: "Album",
              artworkURL: URL(string: "https://i.scdn.co/image/\(id)"), durationMs: 200_000)
    }

    @Test func savesAndLoadsBack() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "aural-snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let snapshot = PlaybackSnapshot(track: track("a"), positionMs: 42_000, contextName: "Mix", upcoming: [track("b")])
        try snapshot.save(to: file)
        #expect(PlaybackSnapshot.load(from: file) == snapshot)
    }

    @Test func upcomingIsBounded() {
        let many = (0..<200).map { track("t\($0)") }
        let snapshot = PlaybackSnapshot(track: track("a"), positionMs: 0, contextName: nil, upcoming: many)
        #expect(snapshot.upcoming.count == PlaybackQueue.limit)
    }

    @Test func restoredTrackShowsPausedAndKeepsSeeks() async throws {
        let source = SoloistSource()
        let snapshot = PlaybackSnapshot(track: track("a"), positionMs: 42_000, contextName: "Mix", upcoming: [])
        await source.restore(snapshot)

        var events = source.events.makeAsyncIterator()
        guard case .stateChanged(let state)? = await events.next() else {
            Issue.record("expected a state")
            return
        }
        #expect(state.track == snapshot.track)
        #expect(state.status == .paused)
        #expect(state.contextName == "Mix")
        #expect(state.position.current() == 42_000)

        // Not connected to Soloist: a seek only moves the saved position.
        try await source.seek(toMs: 10_000)
        #expect(await source.snapshot()?.positionMs == 10_000)
    }

    @Test func failedResumeKeepsTheRestoredTrack() async {
        let source = SoloistSource() // never connected: every command fails
        let snapshot = PlaybackSnapshot(track: track("a"), positionMs: 42_000, contextName: nil, upcoming: [track("b")])
        await source.restore(snapshot)

        await #expect(throws: SoloistError.notConnected) { try await source.resume() }

        // Still restorable: the next play press tries again.
        #expect(await source.snapshot() == snapshot)
    }
}
