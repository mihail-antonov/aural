import SwiftUI

/// Circular progress around the cover, open at the top like the design. It
/// fills from left to right: from 11 o'clock counterclockwise, along the
/// bottom, up to 1 o'clock. It looks like the system slider bent into an arc:
/// a thick rounded track, an accent fill and a glowing accent knob.
///
/// Dragging the knob seeks live; clicking the ring glides the knob to the
/// clicked point. VoiceOver and the arrow keys can adjust it too.
///
/// There is no system control for this, so it is drawn with shapes.
struct ProgressRing: View {
    /// 0…1, from the playback state.
    let progress: Double
    let durationMs: Int
    let canSeek: Bool
    let onSeek: (Int) -> Void

    private static let keyboardStepMs = 10_000
    /// How long a seek target is shown before trusting the reported position again.
    private static let seekHold: Duration = .seconds(2)
    /// A press that moves less than this is a click, not a drag.
    private static let dragThreshold = 3.0
    private static let glide = Animation.smooth(duration: 0.4)

    /// Progress while dragging.
    @State private var dragProgress: Double?
    /// Where the user seeked to, shown until Soloist reports a matching position
    /// (otherwise the ring would jump back for a moment and then forward).
    @State private var seekTarget: Double?
    @State private var seekTargetTask: Task<Void, Never>?
    @State private var isHovered = false
    @FocusState private var isFocused: Bool

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
        .onChange(of: progress) { _, newValue in
            // Soloist caught up with the seek: follow the real position again.
            if let target = seekTarget, abs(newValue - target) < 0.02 { clearSeekTarget() }
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
        seekTarget = fraction
        seekTargetTask?.cancel()
        seekTargetTask = Task {
            try? await Task.sleep(for: Self.seekHold)
            if !Task.isCancelled { seekTarget = nil }
        }
        onSeek(Int(fraction * Double(durationMs)))
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
    // screen coordinates). The ring runs counterclockwise from 11 o'clock
    // (-120°), so progress subtracts from the angle.

    private static let startAngle = -120.0

    static func radius(in size: CGSize) -> Double {
        (min(size.width, size.height) - knobSize) / 2
    }

    private static func arc(to fraction: Double) -> some Shape {
        // `trim` draws clockwise from 3 o'clock. Drawing the arc clockwise from
        // its far end (1 o'clock, -60° = start - sweep) back to the current
        // position gives the counterclockwise-filling look.
        Circle()
            .trim(from: (1 - fraction) * sweep / 360, to: sweep / 360)
            .rotation(.degrees(startAngle - sweep))
    }

    private static func point(at fraction: Double, radius: Double, center: CGPoint) -> CGPoint {
        let radians = (startAngle - fraction * sweep) * .pi / 180
        return CGPoint(x: center.x + radius * cos(radians), y: center.y + radius * sin(radians))
    }

    /// Maps a point to 0…1 along the ring; points in the top gap snap to the nearer end.
    static func fraction(at location: CGPoint, center: CGPoint) -> Double {
        let degrees = atan2(location.y - center.y, location.x - center.x) * 180 / .pi
        var relative = (startAngle - degrees).truncatingRemainder(dividingBy: 360)
        if relative < 0 { relative += 360 }
        if relative > sweep {
            relative = relative > sweep + (360 - sweep) / 2 ? 0 : sweep
        }
        return relative / sweep
    }
}

#Preview {
    ProgressRing(progress: 0.35, durationMs: 215_000, canSeek: true) { _ in }
        .frame(width: 240, height: 240)
        .padding()
        .background(.black)
}
