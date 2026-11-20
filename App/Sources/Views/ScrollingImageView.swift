import AppKit
import QuartzCore
import SwiftUI

/// Slides an image (a line of text drawn by `MarqueeText`) to the left in
/// rounds, with Core Animation, so the system's render server does the work
/// and Aural does nothing per frame. Each round rests for `pause` seconds,
/// then moves two copies of the image left until the second copy sits
/// exactly where the first one started, and starts over (invisibly).
/// Both edges fade softly.
///
/// Like `SpinningCoverImage`, the view owns its layers, so AppKit leaves them alone.
struct ScrollingImageView: NSViewRepresentable {
    let image: CGImage
    /// Pixels per point the image was drawn at.
    let scale: Double
    let gap: Double
    /// Points per second.
    let speed: Double
    let pause: Double
    /// Width of the soft fade at each edge.
    let fade: Double

    func makeNSView(context: Context) -> ScrollingImageLayerView { ScrollingImageLayerView() }

    func updateNSView(_ view: ScrollingImageLayerView, context: Context) {
        view.configuration = .init(image: image, scale: scale, gap: gap, speed: speed, pause: pause, fade: fade)
    }
}

final class ScrollingImageLayerView: NSView {
    struct Configuration: Equatable {
        let image: CGImage
        let scale: Double
        let gap: Double
        let speed: Double
        let pause: Double
        let fade: Double

        static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.image === rhs.image && lhs.scale == rhs.scale && lhs.gap == rhs.gap
                && lhs.speed == rhs.speed && lhs.pause == rhs.pause && lhs.fade == rhs.fade
        }
    }

    /// Rebuilt only when it changes, not on every SwiftUI update.
    var configuration: Configuration? {
        didSet { if configuration != oldValue { rebuild() } }
    }

    /// Clips to the view and fades the edges (through its mask).
    private let container = CALayer()
    private let edgeFade = CAGradientLayer()
    /// The two copies side by side; this layer is what moves.
    private let strip = CALayer()
    private let first = CALayer()
    private let second = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        // Setting `layer` before `wantsLayer` makes this a layer-hosting view:
        // AppKit then never changes the layers below it.
        layer = CALayer()
        wantsLayer = true

        container.masksToBounds = true
        layer?.addSublayer(container)

        edgeFade.startPoint = CGPoint(x: 0, y: 0.5)
        edgeFade.endPoint = CGPoint(x: 1, y: 0.5)
        edgeFade.colors = [NSColor.clear, .black, .black, .clear].map(\.cgColor)
        container.mask = edgeFade

        // The strip is placed by its left edge, so moving it is simple.
        strip.anchorPoint = CGPoint(x: 0, y: 0.5)
        container.addSublayer(strip)
        for copy in [first, second] {
            copy.contentsGravity = .resize
            strip.addSublayer(copy)
        }
    }

    // Only created from code (`ScrollingImageView`), never from a storyboard.
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    /// Clicks go to the SwiftUI views around it.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard container.frame != bounds else { return }
        rebuild()
    }

    /// Lays out the copies and starts the rounds from the beginning.
    private func rebuild() {
        guard let configuration, bounds.width > 0 else { return }
        let width = Double(configuration.image.width) / configuration.scale
        let height = Double(configuration.image.height) / configuration.scale
        let distance = width + configuration.gap

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // In a layer-hosting view, sizing the root layer is up to us.
        layer?.frame = bounds
        container.frame = bounds
        edgeFade.frame = container.bounds
        let fade = configuration.fade / bounds.width
        edgeFade.locations = [0, fade, 1 - fade, 1].map { NSNumber(value: $0) }

        strip.bounds = CGRect(x: 0, y: 0, width: width + distance, height: height)
        strip.position = CGPoint(x: 0, y: bounds.midY)
        for (index, copy) in [first, second].enumerated() {
            copy.contents = configuration.image
            copy.contentsScale = configuration.scale
            copy.frame = CGRect(x: Double(index) * distance, y: 0, width: width, height: height)
        }

        // One round: rest, then slide by `distance` at an even speed. The
        // end looks exactly like the start, so the repeat is invisible.
        let slide = distance / configuration.speed
        let round = configuration.pause + slide
        let scroll = CAKeyframeAnimation(keyPath: "position.x")
        scroll.values = [0, 0, -distance]
        scroll.keyTimes = [0, NSNumber(value: configuration.pause / round), 1]
        scroll.duration = round
        scroll.repeatCount = .infinity
        // Kept even if the view leaves the window for a moment.
        scroll.isRemovedOnCompletion = false
        strip.removeAllAnimations()
        strip.add(scroll, forKey: "scroll")
        CATransaction.commit()
    }
}
