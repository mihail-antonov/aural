import SwiftUI

/// Circular progress around the cover, open at the top like the design. It
/// fills from right to left: from 1 o'clock clockwise, along the bottom, up
/// to 11 o'clock. It looks like the system slider bent into an arc:
/// a thick rounded track, an accent fill and a glowing accent knob.
///
/// Dragging the knob seeks live; clicking the ring glides the knob to the
/// clicked point. When the track changes, the knob glides back to the start
/// instead of jumping. VoiceOver and the arrow keys can adjust it too.
///
/// There is no system control for this, so it is drawn with shapes.
struct ProgressRing: View {
    /// 0…1, from the playback state.
    let progress: Double
    /// The track `progress` belongs to; a change glides the knob back to 0.
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
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

    /// How often the ring is redrawn while playing. On a 3-minute song the
    /// knob moves about half a point per redraw. (30 per second cost a lot
    /// of CPU for a ring that barely moves; 4 per second looked choppy.)
    static let redrawInterval = 1.0 / 8

    private var shownProgress: Double { min(max(dragProgress ?? seekTarget ?? progress, 0), 1) }

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let radius = RingDrawing.radius(in: geometry.size)

            RingDrawing(
                progress: shownProgress,
                isEmphasized: canSeek && (isHovered || isFocused || dragProgress != nil),
                canSeek: canSeek
            )
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
        .onChange(of: Reported(trackID: trackID, progress: progress)) { old, new in
            if old.trackID != new.trackID {
                // Not on launch (no previous track): the restored position is real.
                guard old.trackID != nil, new.trackID != nil else { return }
                trackChanged(from: seekTarget ?? old.progress)
            } else if let target = seekTarget, abs(new.progress - target) < 0.02, Date.now >= holdUntil {
                // Soloist caught up with the seek: follow the real position again.
                clearSeekTarget()
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
                    dragProgress = RingDrawing.fraction(at: value.location, center: center)
                }
            }
            .onEnded { value in
                guard startsOnRing(value, center: center, radius: radius) else { return }
                let fraction = RingDrawing.fraction(at: value.location, center: center)
                if dragProgress != nil {
                    // The knob is already there: hand over without animating.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        dragProgress = nil
                        seek(to: fraction)
                    }
                } else {
                    withAnimation(Self.glide) { seek(to: fraction) }
                }
            }
    }

    private func startsOnRing(_ value: DragGesture.Value, center: CGPoint, radius: Double) -> Bool {
        hypot(value.startLocation.x - center.x, value.startLocation.y - center.y) > radius - 24
    }

    private func seek(to fraction: Double) {
        hold(at: fraction)
        onSeek(Int(fraction * Double(durationMs)))
    }

    /// Shows `fraction` until the reported position matches it (at most `seekHold`).
    private func hold(at fraction: Double) {
        seekTarget = fraction
        holdUntil = .now + Self.glideDuration
        seekTargetTask?.cancel()
        seekTargetTask = Task {
            try? await Task.sleep(for: Self.seekHold)
            if !Task.isCancelled { seekTarget = nil }
        }
    }

    /// A new track starts at 0, but the first report after a skip can still
    /// carry the old position. The knob stays where it was for one frame,
    /// then glides back to the start, and follows the new track's real
    /// position once Soloist reports it.
    private func trackChanged(from previous: Double) {
        guard dragProgress == nil else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { hold(at: previous) }
        Task {
            // The next frame, so the glide starts from the old position.
            try? await Task.sleep(for: .milliseconds(16))
            withAnimation(Self.glide) { hold(at: 0) }
        }
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
        withAnimation(Self.glide) { seek(to: target / Double(durationMs)) }
        return .handled
    }
}

/// What `onChange` compares: a new track and a new position can arrive together.
private struct Reported: Equatable {
    let trackID: String?
    let progress: Double
}

/// Draws the track, the fill and the knob for one progress value.
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

    /// Gap at the top between 11 and 1 o'clock; the ring covers the other 300°.
    static let sweep = 300.0
    static let lineWidth = 4.0
    static let knobSize = 14.0

    var body: some View {
        GeometryReader { geometry in
            let radius = Self.radius(in: geometry.size)
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)

            ZStack {
                // The arcs are inset by half a knob so the knob never sticks out of the frame.
                Group {
                    Self.arc(to: 1)
                        .stroke(.white.opacity(0.18), style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                    Self.arc(to: progress)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                }
                .padding(Self.knobSize / 2)

                // The knob as in the design: an accent dot with a soft glow,
                // which gets stronger on hover, focus and drag.
                Circle()
                    .fill(Theme.accent)
                    .frame(width: Self.knobSize, height: Self.knobSize)
                    .shadow(color: Theme.accent.opacity(isEmphasized ? 1 : 0.8), radius: isEmphasized ? 9 : 4)
                    .animation(.smooth(duration: 0.2), value: isEmphasized)
                    .position(Self.point(at: progress, radius: radius, center: center))
                    .opacity(canSeek ? 1 : 0.5)
            }
        }
    }

    // MARK: - Geometry
    //
    // Angles are in degrees, measured clockwise from 3 o'clock (SwiftUI's
    // screen coordinates). The ring runs clockwise from 1 o'clock (-60°),
    // so progress adds to the angle.

    private static let startAngle = -60.0

    static func radius(in size: CGSize) -> Double {
        (min(size.width, size.height) - knobSize) / 2
    }

    private static func arc(to fraction: Double) -> some Shape {
        // `trim` draws clockwise from 3 o'clock; rotating it to the start
        // angle makes it draw clockwise from 1 o'clock.
        Circle()
            .trim(from: 0, to: fraction * sweep / 360)
            .rotation(.degrees(startAngle))
    }

    private static func point(at fraction: Double, radius: Double, center: CGPoint) -> CGPoint {
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
    ProgressRing(progress: 0.35, trackID: "preview", durationMs: 215_000, canSeek: true) { _ in }
        .frame(width: 240, height: 240)
        .padding()
        .background(.black)
}
