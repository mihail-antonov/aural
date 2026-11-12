/// Common interface for everything that can play music: Soloist (Spotify) and,
/// from Stage 6, local files. The rest of Aural talks only to this protocol.
///
/// Commands return as soon as they are sent. The resulting state change arrives
/// later on `events` — callers should not assume a command took effect.
public protocol PlaybackSource: Sendable {
    /// Stream of state changes. There is a single consumer (the app's model).
    var events: AsyncStream<PlaybackEvent> { get }

    func play(uri: String) async throws
    func resume() async throws
    func pause() async throws
    func next() async throws
    func previous() async throws
    func seek(toMs positionMs: Int) async throws
    /// 0–100.
    func setVolume(_ volume: Int) async throws
    func setShuffle(_ enabled: Bool) async throws
    func setRepeat(_ mode: RepeatMode) async throws
}
