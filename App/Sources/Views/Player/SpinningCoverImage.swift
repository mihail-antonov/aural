import AppKit
import QuartzCore
import SwiftUI

/// The album art, round, turning slowly like a record while `isSpinning`.
///
/// Turned by Core Animation, not by SwiftUI: a SwiftUI rotation makes the
/// whole window redraw for every frame (5–8 % CPU, measured), while a Core
/// Animation rotation runs in the system's render server, so Aural does no
/// work per frame at all. Pausing keeps the angle, and spinning continues
/// from there.
///
/// The view owns its layers (a "layer-hosting" view), so AppKit leaves
/// them alone. Rotating a layer that AppKit manages went wrong once: AppKit
/// reset the point it turns around, and the cover swung around the window.
struct SpinningCoverImage: NSViewRepresentable {
    let image: CGImage
    let isSpinning: Bool

    func makeNSView(context: Context) -> SpinningImageView { SpinningImageView() }

    func updateNSView(_ view: SpinningImageView, context: Context) {
        view.setImage(image)
        view.setSpinning(isSpinning)
    }
}

final class SpinningImageView: NSView {
    /// One slow turn: a real record (33⅓ rpm) would be dizzying.
    private static let secondsPerTurn = 20.0
    private static let spinKey = "spin"

    /// The turning image, a sublayer of the view's own root layer.
    private let imageLayer = CALayer()
    private var isSpinning = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Setting `layer` before `wantsLayer` makes this a layer-hosting view:
        // AppKit then never changes the layers below it.
        layer = CALayer()
        wantsLayer = true
        imageLayer.contentsGravity = .resizeAspectFill
        imageLayer.masksToBounds = true
        layer?.addSublayer(imageLayer)
        addSpin()
        pause()
    }

    // Only created from code (`SpinningCoverImage`), never from a storyboard.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Clicks go to the SwiftUI views around it (the ring seeks).
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        withoutImplicitAnimations {
            // `bounds` and `position`, not `frame`: `frame` is not defined
            // for a rotated layer.
            imageLayer.bounds = CGRect(origin: .zero, size: newSize)
            imageLayer.position = CGPoint(x: newSize.width / 2, y: newSize.height / 2)
            // Half the side makes the square a circle.
            imageLayer.cornerRadius = min(newSize.width, newSize.height) / 2
        }
    }

    func setImage(_ image: CGImage) {
        guard (imageLayer.contents as AnyObject?) !== image else { return }
        withoutImplicitAnimations { imageLayer.contents = image }
    }

    func setSpinning(_ spinning: Bool) {
        guard spinning != isSpinning else { return }
        isSpinning = spinning
        if spinning { resume() } else { pause() }
    }

    // MARK: - Spinning

    /// One endless turn. Negative, because on macOS a positive angle turns
    /// counterclockwise and a record turns clockwise.
    private func addSpin() {
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = 0
        spin.toValue = -2 * Double.pi
        spin.duration = Self.secondsPerTurn
        spin.repeatCount = .infinity
        // Kept even if the system would otherwise drop it (e.g. when the
        // view leaves the window for a moment).
        spin.isRemovedOnCompletion = false
        imageLayer.add(spin, forKey: Self.spinKey)
    }

    // Pausing and resuming a Core Animation animation means stopping the
    // layer's own clock (`speed = 0`) and shifting it on resume, so the
    // animation continues from the same angle (Apple's Technical Q&A QA1673).

    private func pause() {
        let now = imageLayer.convertTime(CACurrentMediaTime(), from: nil)
        imageLayer.speed = 0
        imageLayer.timeOffset = now
    }

    private func resume() {
        if imageLayer.animation(forKey: Self.spinKey) == nil { addSpin() }
        let pausedAt = imageLayer.timeOffset
        imageLayer.speed = 1
        imageLayer.timeOffset = 0
        imageLayer.beginTime = 0
        imageLayer.beginTime = imageLayer.convertTime(CACurrentMediaTime(), from: nil) - pausedAt
    }

    private func withoutImplicitAnimations(_ change: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        change()
        CATransaction.commit()
    }
}
