import Foundation
import Testing
@testable import AuralCore

/// Message shapes come from a real Soloist 1.3.10 trace (Stage 0),
/// with track names and IDs replaced.
struct SoloistMessagesTests {
    private func fixture(_ name: String) throws -> Data {
        let url = try #require(Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"))
        return try Data(contentsOf: url)
    }

    private func decode(_ json: String) throws -> SoloistEvent {
        try SoloistEvent.decode(from: Data(json.utf8))
    }

    // MARK: Events

    @Test func decodesPlaybackStateSnapshot() throws {
        guard case .playbackState(let state) = try SoloistEvent.decode(from: fixture("playback_state")) else {
            Issue.record("expected playback_state")
            return
        }
        #expect(state.status == "playing")
        #expect(state.volume == 40)
        #expect(state.position?.positionMs == 23669)
        #expect(state.options?.repeat == "context")
        #expect(state.availableActions?.keys.contains("skip_next") == true)
    }

    @Test func decodesSmallEvents() throws {
        #expect(try decode(#"{"type":"auth_state","logged_in":true,"is_active":false,"device_name":"Aural"}"#)
            == .authState(loggedIn: true, isActive: false))
        #expect(try decode(#"{"type":"playback_changed","status":"buffering"}"#) == .playbackChanged(status: "buffering"))
        #expect(try decode(#"{"type":"volume_changed","volume":30}"#) == .volumeChanged(30))
        #expect(try decode(#"{"type":"device_changed","is_active":true,"device_name":"Aural"}"#) == .deviceChanged(isActive: true))
        #expect(try decode(#"{"type":"command_result","command":"pause"}"#) == .commandResult(command: "pause"))
        #expect(try decode(#"{"type":"error","message":"command requires authentication"}"#)
            == .error(message: "command requires authentication"))
        #expect(try decode(#"{"type":"position_sync","position":{"position_ms":24791,"timestamp_ms":1794481515068,"speed":1}}"#)
            == .positionSync(.init(positionMs: 24791, timestampMs: 1794481515068, speed: 1)))
    }

    @Test func queueContentsAreNotDecodedYet() throws {
        #expect(try SoloistEvent.decode(from: fixture("queue_changed")) == .queueChanged)
    }

    @Test func unknownEventTypesAreIgnoredNotErrors() throws {
        #expect(try decode(#"{"type":"something_new","x":1}"#) == .unknown(type: "something_new"))
    }

    @Test func malformedMessagesThrow() {
        #expect(throws: (any Error).self) { try decode(#"{"no_type":true}"#) }
        #expect(throws: (any Error).self) { try decode(#"{"type":"volume_changed"}"#) }
    }

    // MARK: Commands

    private func json(_ command: SoloistCommand) throws -> [String: AnyHashable] {
        let data = try JSONEncoder().encode(command)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: AnyHashable])
    }

    @Test func encodesCommands() throws {
        #expect(try json(.play(uri: "spotify:album:1")) == ["type": "command", "command": "play", "uri": "spotify:album:1"])
        #expect(try json(.play(uri: nil)) == ["type": "command", "command": "play"])
        #expect(try json(.skipPrevious) == ["type": "command", "command": "skip_prev"])
        #expect(try json(.seek(positionMs: 30000)) == ["type": "command", "command": "seek", "position_ms": 30000])
        #expect(try json(.setVolume(55)) == ["type": "command", "command": "set_volume", "volume": 55])
        #expect(try json(.setShuffle(true)) == ["type": "command", "command": "set_shuffle", "enabled": true])
    }

    @Test(arguments: [
        (RepeatMode.off, [SoloistCommand.setRepeatTrack(false), .setRepeatContext(false)]),
        (.context, [.setRepeatTrack(false), .setRepeatContext(true)]),
        (.track, [.setRepeatContext(false), .setRepeatTrack(true)]),
    ])
    func mapsRepeatModeToTwoFlags(mode: RepeatMode, expected: [SoloistCommand]) {
        #expect(SoloistCommand.commands(for: mode) == expected)
    }
}
