import SwiftUI
import AuralCore

/// Circular progress around the cover, open at the top like the design. It
/// fills from right to left: from 1 o'clock clockwise, along the bottom, up
/// to 11 o'clock. It looks like the system slider bent into an arc:
/// a thick rounded track, an accent fill and a glowing accent knob.
///
/// Dragging the knob seeks live; clicking the ring glides the knob to the
/// clicked point. When the track changes, the knob glides back to the start
/// instead of jumping. VoiceOver and the arrow keys can adjust it too.
///
/// There is no system control for this, so it is drawn with shapes, in two layers:
/// - While the song simply plays, `LiveRingView` draws the ring and Core
///   Animation moves the fill and the knob, so Aural does no work per frame
///   (redrawing it with SwiftUI cost about 6 % CPU, measured).
/// - While the user drags, or the knob glides to a new place, SwiftUI draws
///   the fill and the knob on top (`RingDrawing`) and the live ones are hidden.
struct ProgressRing: View {
    /// The reported position; the ring works out the current one from it.
    let position: PlaybackPosition
    let isPlaying: Bool
    /// The track `position` belongs to; a change glides the knob back to 0.
    let trackID: String?
    let durationMs: Int
    let canSeek: Bool
    let onSeek: (Int) -> Void

    private static let keyboardStepMs = 10_000
    /// How long a seek target is shown before trusting the reported position again.
    private static let seekHold: Duration = .seconds(2)
    /// A press that moves less than this is a click, not a drag.
    private static let dragThreshold = 3.0
    private static let glideDuration = 0.3
    private static let glide = Animation.smooth(duration: glideDuration)

    /// Progress while dragging.
    @State private var dragProgress: Double?
    /// Where the user seeked to, shown until Soloist reports a matching position
    /// (otherwise the ring would jump back for a moment and then forward).
    @State private var seekTarget: Double?
    @State private var seekTargetTask: Task<Void, Never>?
    /// The seek target is kept at least until its glide has finished:
    /// switching to the reported position mid-glide would make it jump.
    @State private var holdUntil = Date.distantPast
    /// A report matched the seek target while the glide was still running.
    @State private var seekCaughtUp = false
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    /// 0…1, worked out from the reported position at `date`.
    private func liveProgress(at date: Date = .now) -> Double {
        Self.progress(of: position, durationMs: durationMs, at: date)
    }

    private static func progress(of position: PlaybackPosition, durationMs: Int, at date: Date = .now) -> Double {
        guard durationMs > 0 else { return 0 }
        return Double(position.current(at: date, durationMs: durationMs)) / Double(durationMs)
    }

    /// SwiftUI draws the fill and the knob (dragging, gliding, holding a
    /// seek target); otherwise the live Core Animation layers do.
    private var isManual: Bool { dragProgress != nil || seekTarget != nil }

    private var shownProgress: Double { min(max(dragProgress ?? seekTarget ?? liveProgress(), 0), 1) }

    private var isEmphasized: Bool { canSeek && (isHovered || isFocused || dragProgress != nil) }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = RingGeometry.radius(in: geometry.size)

            ZStack {
                LiveRingView(
                    position: position,
                    isPlaying: isPlaying,
                    durationMs: durationMs,
                    showsProgress: !isManual,
                    isEmphasized: isEmphasized,
                    canSeek: canSeek
                )
                RingDrawing(
                    progress: shownProgress,
                    isEmphasized: isEmphasized,
                    canSeek: canSeek
                )
                .opacity(isManual ? 1 : 0)
            }
            .contentShape(.rect)
            .gesture(seekGesture(center: center, radius: radius), isEnabled: canSeek)
        }
        .onHover { isHovered = $0 }
        .focusable(canSeek)
        .focused($isFocused)
        // No rectangular focus ring; the knob glows instead.
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { step(-Self.keyboardStepMs) }
        .onKeyPress(.rightArrow) { step(Self.keyboardStepMs) }
        .onChange(of: Reported(trackID: trackID, position: position, durationMs: durationMs)) { old, new in
            if old.trackID != new.trackID {
                // Not on launch (no previous track): the restored position is real.
                guard old.trackID != nil, new.trackID != nil else { return }
                let oldProgress = Self.progress(of: old.position, durationMs: old.durationMs)
                trackChanged(from: dragProgress ?? seekTarget ?? oldProgress)
            } else if caughtUpWithSeek {
                // Soloist caught up with the seek: follow the real position
                // again, but not in the middle of the glide (it would jump).
                if Date.now >= holdUntil { clearSeekTarget() } else { seekCaughtUp = true }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Playback position")
        .accessibilityValue("\(formatTime(Int(shownProgress * Double(durationMs)))) of \(formatTime(durationMs))")
        .accessibilityAdjustableAction { direction in
            _ = step(direction == .increment ? Self.keyboardStepMs : -Self.keyboardStepMs)
        }
    }

    // MARK: - Seeking

    /// Only presses that start on the ring (not on the cover) seek.
    private func seekGesture(center: CGPoint, radius: Double) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard startsOnRing(value, center: center, radius: radius) else { return }
                let moved = hypot(value.translation.width, value.translation.height) > Self.dragThreshold
                if moved || dragProgress != nil {
                    dragProgress = RingGeometry.fraction(at: value.location, center: center)
                }
            }
            .onEnded { value in
                guard startsOnRing(value, center: center, radius: radius) else { return }
                let fraction = RingGeometry.fraction(at: value.location, center: center)
                if dragProgress != nil {
                    // The knob is already there: hand over without animating.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        dragProgress = nil
                        seek(to: fraction)
                    }
                } else {
                    seek(to: fraction, gliding: true)
                }
            }
    }

    private func startsOnRing(_ value: DragGesture.Value, center: CGPoint, radius: Double) -> Bool {
        hypot(value.startLocation.x - center.x, value.startLocation.y - center.y) > radius - 24
    }

    private func seek(to fraction: Double, gliding: Bool = false) {
        onSeek(Int(fraction * Double(durationMs)))
        if gliding { glide(to: fraction) } else { hold(at: fraction) }
    }

    /// Moves the knob smoothly along the arc to `fraction`.
    private func glide(to fraction: Double, from start: Double? = nil) {
        if isManual, start == nil {
            // SwiftUI already draws the knob: glide from where it is.
            withAnimation(Self.glide) { hold(at: fraction) }
            return
        }
        // Hand over from the live layers: SwiftUI's knob appears where the
        // live one was, without animating, and glides from there a frame later.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { hold(at: start ?? liveProgress()) }
        Task {
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(Self.glide) { hold(at: fraction) }
        }
    }

    /// Whether the reported position has reached the seek target.
    private var caughtUpWithSeek: Bool {
        guard let seekTarget else { return false }
        return abs(liveProgress() - seekTarget) < 0.02
    }

    /// Shows `fraction` until the reported position matches it (at most `seekHold`).
    private func hold(at fraction: Double) {
        seekTarget = fraction
        seekCaughtUp = false
        holdUntil = .now + Self.glideDuration
        seekTargetTask?.cancel()
        seekTargetTask = Task {
            // Once the glide is over, follow the real position if a report
            // already matched during the glide (no new one may come).
            // (`seekCaughtUp` is state, so this reads its current value.)
            try? await Task.sleep(for: .seconds(Self.glideDuration))
            guard !Task.isCancelled else { return }
            if seekCaughtUp { seekTarget = nil; return }
            try? await Task.sleep(for: Self.seekHold - .seconds(Self.glideDuration))
            if !Task.isCancelled { seekTarget = nil }
        }
    }

    /// A new track starts at 0, but the first report after a skip can still
    /// carry the old position. The knob stays where it was for one frame,
    /// then glides back to the start, and follows the new track's real
    /// position once Soloist reports it.
    private func trackChanged(from previous: Double) {
        guard dragProgress == nil else { return }
        glide(to: 0, from: previous)
    }

    private func clearSeekTarget() {
        seekTargetTask?.cancel()
        seekTargetTask = nil
        seekTarget = nil
    }

    private func step(_ deltaMs: Int) -> KeyPress.Result {
        guard canSeek, durationMs > 0 else { return .ignored }
        let current = shownProgress * Double(durationMs)
        let target = min(max(current + Double(deltaMs), 0), Double(durationMs))
        seek(to: target / Double(durationMs), gliding: true)
        return .handled
    }
}

/// What `onChange` compares: a new track and a new position can arrive together.
private struct Reported: Equatable {
    let trackID: String?
    let position: PlaybackPosition
    let durationMs: Int
}

/// Draws the fill and the knob for one progress value, above the live
/// ring while dragging or gliding.
///
/// Conforming to `Animatable` lets SwiftUI animate `progress` itself: during a
/// glide every frame redraws the fill and moves the knob *along the arc*
/// (animating the knob's position directly would move it in a straight line).
private struct RingDrawing: View, Animatable {
    var progress: Double
    let isEmphasized: Bool
    let canSeek: Bool

    // `nonisolated`: SwiftUI's animation system reads this outside the main
    // actor. It only touches a plain `Double` stored in this struct, so that is safe.
    nonisolated var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let radius = RingGeometry.radius(in: geometry.size)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // Inset by half a knob so the knob never sticks out of the frame.
                Self.arc(to: progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: RingGeometry.lineWidth, lineCap: .round))
                    .padding(RingGeometry.knobSize / 2)

                Circle()
                    .fill(Theme.accent)
                    .frame(width: RingGeometry.knobSize, height: RingGeometry.knobSize)
                    .shadow(
                        color: Theme.accent.opacity(RingGeometry.glowOpacity(isEmphasized)),
                        radius: RingGeometry.glowRadius(isEmphasized)
                    )
                    .animation(.smooth(duration: 0.2), value: isEmphasized)
                    .position(RingGeometry.point(at: progress, radius: radius, center: center))
                    .opacity(canSeek ? 1 : 0.5)
            }
        }
    }

    private static func arc(to fraction: Double) -> some Shape {
        // `trim` draws clockwise from 3 o'clock; rotating it to the start
        // angle makes it draw clockwise from 1 o'clock.
        Circle()
            .trim(from: 0, to: fraction * RingGeometry.sweep / 360)
            .rotation(.degrees(RingGeometry.startAngle))
    }
}

/// The ring's shape and look, shared by the SwiftUI and the Core Animation drawing.
///
/// Angles are in degrees, measured clockwise from 3 o'clock (screen
/// coordinates, y pointing down). The ring runs clockwise from 1 o'clock
/// (-60°), so progress adds to the angle.
enum RingGeometry {
    /// Gap at the top between 11 and 1 o'clock; the ring covers the other 300°.
    static let sweep = 300.0
    static let startAngle = -60.0
    static let lineWidth = 4.0
    static let knobSize = 14.0
    static let trackOpacity = 0.18

    /// The knob's soft glow, stronger on hover, focus and drag.
    static func glowRadius(_ isEmphasized: Bool) -> Double { isEmphasized ? 9 : 4 }
    static func glowOpacity(_ isEmphasized: Bool) -> Double { isEmphasized ? 1 : 0.8 }

    /// The arcs are inset by half a knob so the knob never sticks out of the frame.
    static func radius(in size: CGSize) -> Double {
        (min(size.width, size.height) - knobSize) / 2
    }

    static func point(at fraction: Double, radius: Double, center: CGPoint) -> CGPoint {
        let radians = (startAngle + fraction * sweep) * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    /// Maps a point to 0…1 along the ring; points in the top gap snap to the nearer end.
    static func fraction(at location: CGPoint, center: CGPoint) -> Double {
        let degrees = atan2(location.y - center.y, location.x - center.x) * 180 / .pi
        var relative = (degrees - startAngle).truncatingRemainder(dividingBy: 360)
        if relative < 0 { relative += 360 }
        if relative > sweep {
            relative = relative > sweep + (360 - sweep) / 2 ? 0 : sweep
        }
        return relative / sweep
    }
}

#Preview {
    ProgressRing(
        position: PlaybackPosition(positionMs: 75_000, timestamp: .now, speed: 1),
        isPlaying: true, trackID: "preview", durationMs: 215_000, canSeek: true
    ) { _ in }
        .frame(width: 240, height: 240)
        .padding()
        .background(.black)
}
