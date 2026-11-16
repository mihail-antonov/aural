/// The interface the app uses to control playback, implemented by the
/// Soloist (Spotify) source. The rest of Aural talks only to this protocol,
/// so it never sees Soloist's message format.
///
/// Commands return as soon as they are sent. The resulting state change arrives
/// later on `events` — callers should not assume a command took effect.
public protocol PlaybackSource: Sendable {
    /// Stream of state changes. There is a single consumer (the app's model).
    var events: AsyncStream<PlaybackEvent> { get }

    /// Plays a playlist or album (or a single track) from the start.
    func play(uri: String) async throws
    /// Plays `tracks[index]`, then the tracks after it in order. The tracks'
    /// details are shown in the queue.
    func play(tracks: [Track], startingAt index: Int) async throws
    /// Plays an entry of the current queue, skipping the ones before it.
    /// Only when `PlaybackQueue.canJump` is true.
    func jump(toQueueEntry id: QueueEntry.ID) async throws
    func resume() async throws
    func pause() async throws
    func next() async throws
    func previous() async throws
    func seek(toMs positionMs: Int) async throws
    /// 0–100.
    func setVolume(_ volume: Int) async throws
    func setShuffle(_ enabled: Bool) async throws
    func setRepeat(_ mode: RepeatMode) async throws
    /// Removes queued songs and the rest of a list being played (see
    /// `PlaybackQueue.canClear`). The current song keeps playing.
    func clearQueue() async throws
    /// Moves playback from another device to this one and plays.
    func playHere() async throws
    /// Adds a track to the end of the queue.
    func addToQueue(uri: String) async throws
    /// What is playing now, to be restored on the next launch. Nil when
    /// nothing is loaded.
    func snapshot() async -> PlaybackSnapshot?
    /// Shows a saved snapshot as the paused current track while the engine
    /// has nothing loaded; `resume()` then plays it from the saved position.
    /// Ignored once the engine reports a track of its own.
    func restore(_ snapshot: PlaybackSnapshot) async
}
