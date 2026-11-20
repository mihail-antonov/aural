import AppKit
import AuralCore
import QuartzCore
import SwiftUI

/// The progress ring as Core Animation layers: the faint track, plus the
/// accent fill and the knob, which move by themselves while playing.
///
/// On every new position report (play, pause, seek, new track) the view
/// starts one animation from the current position to the end of the song,
/// lasting as long as the rest of the song. The system's render server then
/// moves the fill and the knob smoothly at the screen's frame rate, and
/// Aural does nothing until the next report. Like `SpinningCoverImage`, the
/// view owns its layers, so AppKit leaves them alone.
///
/// Gestures, hover, focus and VoiceOver stay in SwiftUI (`ProgressRing`).
struct LiveRingView: NSViewRepresentable {
    let position: PlaybackPosition
    let isPlaying: Bool
    let durationMs: Int
    /// False while SwiftUI draws the fill and the knob (dragging, gliding).
    let showsProgress: Bool
    let isEmphasized: Bool
    let canSeek: Bool

    func makeNSView(context: Context) -> LiveRingLayerView { LiveRingLayerView() }

    func updateNSView(_ view: LiveRingLayerView, context: Context) {
        view.update(
            motion: .init(position: position, isPlaying: isPlaying, durationMs: durationMs),
            showsProgress: showsProgress,
            isEmphasized: isEmphasized,
            canSeek: canSeek
        )
    }
}

final class LiveRingLayerView: NSView {
    /// What the animation is built from; it is rebuilt only when this changes,
    /// not on every SwiftUI update (e.g. hover).
    struct Motion: Equatable {
        let position: PlaybackPosition
        let isPlaying: Bool
        let durationMs: Int
    }

    /// Holds the ring layers with y pointing down, so the shared
    /// `RingGeometry` (written for SwiftUI's coordinates) works unchanged.
    private let container = CALayer()
    private let track = CAShapeLayer()
    private let fill = CAShapeLayer()
    private let knob = CALayer()
    private var motion: Motion?

    /// Points per arc segment: small enough that the polyline looks round.
    private static let segmentLength = 1.0

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Setting `layer` before `wantsLayer` makes this a layer-hosting view:
        // AppKit then never changes the layers below it.
        layer = CALayer()
        wantsLayer = true

        container.isGeometryFlipped = true
        layer?.addSublayer(container)

        let accent = NSColor(Theme.accent).cgColor
        for (shape, color) in [(track, NSColor.white.withAlphaComponent(RingGeometry.trackOpacity).cgColor), (fill, accent)] {
            shape.fillColor = nil
            shape.strokeColor = color
            shape.lineWidth = RingGeometry.lineWidth
            shape.lineCap = .round
            shape.lineJoin = .round
            container.addSublayer(shape)
        }
        fill.strokeEnd = 0

        knob.bounds = CGRect(x: 0, y: 0, width: RingGeometry.knobSize, height: RingGeometry.knobSize)
        knob.cornerRadius = RingGeometry.knobSize / 2
        knob.backgroundColor = accent
        knob.shadowColor = accent
        knob.shadowOffset = .zero
        // The glow is a circle around a circle: give its shape up front, so
        // the render server need not work it out from the layer's pixels.
        knob.shadowPath = CGPath(ellipseIn: knob.bounds, transform: nil)
        container.addSublayer(knob)
        setGlow(emphasized: false)
    }

    // Only created from code (`LiveRingView`), never from a storyboard.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Clicks and drags go to the SwiftUI ring above.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        // Shape layers are drawn as bitmaps: match the screen's pixel density.
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in [container, track, fill, knob] { sublayer.contentsScale = scale }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    /// Fits the layers to the view every time AppKit lays it out. The root
    /// layer is set to the view's bounds too: in a layer-hosting view that is
    /// up to us (see `SpinningImageView.layout`).
    override func layout() {
        super.layout()
        guard container.frame != bounds else { return }
        withoutImplicitAnimations {
            layer?.frame = bounds
            container.frame = bounds
            let path = arcPath(from: 0)
            track.path = path
            fill.path = path
        }
        restartMotion()
    }

    func update(motion: Motion, showsProgress: Bool, isEmphasized: Bool, canSeek: Bool) {
        withoutImplicitAnimations {
            fill.isHidden = !showsProgress
            knob.isHidden = !showsProgress
            knob.opacity = canSeek ? 1 : 0.5
        }
        // Not wrapped: the glow fades with the layer's own short animation.
        setGlow(emphasized: isEmphasized)
        if motion != self.motion {
            self.motion = motion
            restartMotion()
        }
    }

    private func setGlow(emphasized: Bool) {
        knob.shadowRadius = RingGeometry.glowRadius(emphasized)
        knob.shadowOpacity = Float(RingGeometry.glowOpacity(emphasized))
    }

    // MARK: - Motion

    /// Puts the fill and the knob at the current position and, while
    /// playing, animates them from there to the end of the song.
    private func restartMotion() {
        guard let motion, bounds.width > 0 else { return }
        let durationMs = motion.durationMs
        let progress = durationMs > 0
            ? Double(motion.position.current(durationMs: durationMs)) / Double(durationMs)
            : 0
        let remaining = (1 - progress) * Double(durationMs) / 1000

        withoutImplicitAnimations {
            fill.removeAllAnimations()
            knob.removeAllAnimations()
            fill.strokeEnd = progress
            knob.position = point(at: progress)

            guard motion.isPlaying, motion.position.speed > 0, remaining > 0.05 else { return }
            let duration = remaining / motion.position.speed

            let grow = CABasicAnimation(keyPath: "strokeEnd")
            grow.fromValue = progress
            grow.toValue = 1
            add(grow, duration: duration, to: fill)

            // Along the arc, at an even speed ("paced").
            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = arcPath(from: progress)
            move.calculationMode = .paced
            add(move, duration: duration, to: knob)
        }
    }

    private func add(_ animation: CAAnimation, duration: Double, to layer: CALayer) {
        animation.duration = duration
        // Linear: the song plays at a steady speed.
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        // At the end the fill stays full until the next report.
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "progress")
    }

    // MARK: - Geometry

    private var radius: Double { RingGeometry.radius(in: bounds.size) }
    private var center: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    private func point(at fraction: Double) -> CGPoint {
        RingGeometry.point(at: fraction, radius: radius, center: center)
    }

    /// The arc from `start` (0…1) to the end of the ring, as short straight
    /// segments built from `RingGeometry.point`, so it matches the SwiftUI
    /// drawing exactly. (Even segments also keep `strokeEnd`, which
    /// measures along the path, in step with the progress.)
    private func arcPath(from start: Double) -> CGPath {
        let path = CGMutablePath()
        let length = (1 - start) * radius * 2 * .pi * RingGeometry.sweep / 360
        let segments = max(Int(length / Self.segmentLength), 1)
        path.move(to: point(at: start))
        for index in 1...segments {
            path.addLine(to: point(at: start + (1 - start) * Double(index) / Double(segments)))
        }
        return path
    }

    private func withoutImplicitAnimations(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}
