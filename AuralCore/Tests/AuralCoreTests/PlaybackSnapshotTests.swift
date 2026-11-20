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

    @Test func volumeIsSavedAndOldFilesStillLoad() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "aural-snapshot-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let snapshot = PlaybackSnapshot(track: track("a"), positionMs: 0, contextName: nil, upcoming: [], volume: 100)
        try snapshot.save(to: file)
        #expect(PlaybackSnapshot.load(from: file)?.volume == 100)

        // A file from before the volume was kept.
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        json["volume"] = nil
        try JSONSerialization.data(withJSONObject: json).write(to: file)
        let old = try #require(PlaybackSnapshot.load(from: file))
        #expect(old.volume == nil)
        #expect(old.track == snapshot.track)
    }

    @Test func restoredVolumeIsShownAndChangesAreRemembered() async throws {
        let source = SoloistSource() // never connected
        await source.restore(PlaybackSnapshot(track: track("a"), positionMs: 0, contextName: nil, upcoming: [], volume: 100))

        var events = source.events.makeAsyncIterator()
        guard case .stateChanged(let state)? = await events.next() else {
            Issue.record("expected a state")
            return
        }
        #expect(state.volume == 100)
        #expect(await source.snapshot()?.volume == 100)

        // Not connected, so sending fails, but the choice is remembered.
        await #expect(throws: SoloistError.notConnected) { try await source.setVolume(60) }
        #expect(await source.snapshot()?.volume == 60)
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
