import Foundation

// Wire format of Soloist's WebSocket API (JSON text frames).
// Reference: https://developer.spotify.com/documentation/soloist/reference/websocket-api
//
// Only the fields Aural uses are decoded. Everything else in a message is
// ignored, so large payloads are never kept in memory.

// MARK: - Commands (client → Soloist)

enum SoloistCommand: Sendable, Equatable {
    case getAuthState
    case getState
    case play(uri: String?)
    case pause
    case skipNext
    case skipPrevious
    case seek(positionMs: Int)
    case setVolume(Int)
    case setShuffle(Bool)
    case setRepeatContext(Bool)
    case setRepeatTrack(Bool)

    /// Soloist has two independent repeat flags; Aural has one three-way mode.
    /// The flag that gets switched off is sent first, so both are never on at once.
    static func commands(for mode: RepeatMode) -> [SoloistCommand] {
        switch mode {
        case .off: [.setRepeatTrack(false), .setRepeatContext(false)]
        case .context: [.setRepeatTrack(false), .setRepeatContext(true)]
        case .track: [.setRepeatContext(false), .setRepeatTrack(true)]
        }
    }
}

extension SoloistCommand: Encodable {
    private enum CodingKeys: String, CodingKey {
        case type, command, uri, enabled, volume
        case positionMs = "position_ms"
    }

    var name: String {
        switch self {
        case .getAuthState: "get_auth_state"
        case .getState: "get_state"
        case .play: "play"
        case .pause: "pause"
        case .skipNext: "skip_next"
        case .skipPrevious: "skip_prev"
        case .seek: "seek"
        case .setVolume: "set_volume"
        case .setShuffle: "set_shuffle"
        case .setRepeatContext: "set_repeat_context"
        case .setRepeatTrack: "set_repeat_track"
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("command", forKey: .type)
        try container.encode(name, forKey: .command)
        switch self {
        case .play(let uri): try container.encodeIfPresent(uri, forKey: .uri)
        case .seek(let positionMs): try container.encode(positionMs, forKey: .positionMs)
        case .setVolume(let volume): try container.encode(volume, forKey: .volume)
        case .setShuffle(let enabled), .setRepeatContext(let enabled), .setRepeatTrack(let enabled):
            try container.encode(enabled, forKey: .enabled)
        case .getAuthState, .getState, .pause, .skipNext, .skipPrevious:
            break
        }
    }
}

// MARK: - Events (Soloist → client)

enum SoloistEvent: Sendable, Equatable {
    case authState(loggedIn: Bool, isActive: Bool)
    case playbackState(SoloistWire.PlaybackState)
    case trackChanged(SoloistWire.Entity?)
    case playbackChanged(status: String)
    case positionSync(SoloistWire.Position)
    case volumeChanged(Int)
    case optionsChanged(SoloistWire.Options)
    case deviceChanged(isActive: Bool)
    /// Queue contents are not decoded yet (Stage 5).
    case queueChanged
    case contextChanged
    case commandResult(command: String)
    case error(message: String)
    /// A message type this version of Aural does not know. Ignored, not an error.
    case unknown(type: String)

    /// Decodes one JSON text frame. Two passes: first only `type`, then the
    /// payload struct for that type.
    static func decode(from data: Data) throws -> SoloistEvent {
        let decoder = JSONDecoder()
        let type = try decoder.decode(SoloistWire.Envelope.self, from: data).type

        switch type {
        case "auth_state":
            let message = try decoder.decode(SoloistWire.AuthState.self, from: data)
            return .authState(loggedIn: message.loggedIn, isActive: message.isActive ?? false)
        case "playback_state":
            return .playbackState(try decoder.decode(SoloistWire.PlaybackState.self, from: data))
        case "track_changed":
            return .trackChanged(try decoder.decode(SoloistWire.TrackChanged.self, from: data).item)
        case "playback_changed":
            return .playbackChanged(status: try decoder.decode(SoloistWire.PlaybackChanged.self, from: data).status)
        case "position_sync":
            return .positionSync(try decoder.decode(SoloistWire.PositionSync.self, from: data).position)
        case "volume_changed":
            return .volumeChanged(try decoder.decode(SoloistWire.VolumeChanged.self, from: data).volume)
        case "options_changed":
            return .optionsChanged(try decoder.decode(SoloistWire.OptionsChanged.self, from: data).options)
        case "device_changed":
            return .deviceChanged(isActive: try decoder.decode(SoloistWire.DeviceChanged.self, from: data).isActive)
        case "queue_changed":
            return .queueChanged
        case "context_changed":
            return .contextChanged
        case "command_result":
            return .commandResult(command: try decoder.decode(SoloistWire.CommandResult.self, from: data).command)
        case "error":
            return .error(message: try decoder.decode(SoloistWire.ErrorMessage.self, from: data).message)
        default:
            return .unknown(type: type)
        }
    }
}

/// Decodable mirrors of Soloist's JSON. Field names are mapped explicitly with
/// `CodingKeys` (instead of `.convertFromSnakeCase`) so the wire names are
/// visible in the code and dictionary keys are never rewritten.
enum SoloistWire {
    struct Envelope: Decodable { let type: String }

    struct AuthState: Decodable {
        let loggedIn: Bool
        let isActive: Bool?
        enum CodingKeys: String, CodingKey {
            case loggedIn = "logged_in"
            case isActive = "is_active"
        }
    }

    struct PlaybackState: Decodable, Sendable, Equatable {
        let status: String
        let item: Entity?
        let position: Position?
        let volume: Int?
        let isActive: Bool?
        let options: Options?
        /// Keys are action names (`pause`, `skip_next`, …); the values carry
        /// optional details such as `step_ms`, which Aural does not need.
        let availableActions: [String: IgnoredValue]?

        enum CodingKeys: String, CodingKey {
            case status, item, position, volume, options
            case isActive = "is_active"
            case availableActions = "available_actions"
        }
    }

    struct Position: Decodable, Sendable, Equatable {
        let positionMs: Int
        /// Unix epoch milliseconds (Soloist's clock).
        let timestampMs: Int64
        let speed: Double

        enum CodingKeys: String, CodingKey {
            case speed
            case positionMs = "position_ms"
            case timestampMs = "timestamp_ms"
        }
    }

    struct Options: Decodable, Sendable, Equatable {
        let shuffle: Bool
        /// `off`, `context` or `track`.
        let `repeat`: String
    }

    /// Soloist's generic envelope for tracks, albums, artists, playlists, …
    struct Entity: Decodable, Sendable, Equatable {
        let uri: String?
        let entityType: String?
        let decorations: Decorations?

        enum CodingKeys: String, CodingKey {
            case uri, decorations
            case entityType = "entity_type"
        }
    }

    struct Decorations: Decodable, Sendable, Equatable {
        let identity: Identity?
        let visualIdentity: VisualIdentity?
        let parent: Related?
        let creators: [Related]?
        let playback: PlaybackInfo?

        enum CodingKeys: String, CodingKey {
            case identity, parent, creators, playback
            case visualIdentity = "visual_identity"
        }
    }

    struct Identity: Decodable, Sendable, Equatable { let name: String? }

    struct VisualIdentity: Decodable, Sendable, Equatable { let cover: [Cover]? }

    struct Cover: Decodable, Sendable, Equatable {
        let url: String
        /// `small`, `default`, `large` or `xlarge`.
        let size: String?
    }

    /// A related entity (album of a track, artist). Only its name is needed.
    /// A separate type, because a struct cannot contain itself (`Entity` →
    /// `Decorations` → `Entity` would have infinite size).
    struct Related: Decodable, Sendable, Equatable {
        let entity: NamedEntity
    }

    struct NamedEntity: Decodable, Sendable, Equatable {
        let uri: String?
        let decorations: NameOnly?
    }

    struct NameOnly: Decodable, Sendable, Equatable { let identity: Identity? }

    struct PlaybackInfo: Decodable, Sendable, Equatable {
        let durationMs: Int?
        enum CodingKeys: String, CodingKey { case durationMs = "duration_ms" }
    }

    /// Accepts any JSON value and keeps nothing.
    struct IgnoredValue: Decodable, Sendable, Equatable {
        init(from decoder: any Decoder) throws {}
    }

    struct TrackChanged: Decodable { let item: Entity? }
    struct PlaybackChanged: Decodable { let status: String }
    struct PositionSync: Decodable { let position: Position }
    struct VolumeChanged: Decodable { let volume: Int }
    struct OptionsChanged: Decodable { let options: Options }
    struct CommandResult: Decodable { let command: String }
    struct ErrorMessage: Decodable { let message: String }

    struct DeviceChanged: Decodable {
        let isActive: Bool
        enum CodingKeys: String, CodingKey { case isActive = "is_active" }
    }
}
