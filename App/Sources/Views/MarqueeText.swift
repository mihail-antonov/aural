import SwiftUI

/// One line of text that, when it is too long to fit, scrolls sideways to
/// show all of it, like Spotify's song titles: it rests for a moment, glides
/// left until a second copy has taken the first one's place, and starts over
/// (the two copies make the restart invisible). Text that fits is just
/// centered. With Reduce Motion it does not move and ends with "…" instead.
///
/// SwiftUI has no marquee. Moving the text with a SwiftUI animation redrew
/// the window on every frame (10–14 % CPU while scrolling, measured), so the
/// text is drawn once into an image (`ImageRenderer`) and Core Animation
/// slides that image (`ScrollingImageView`): Aural does no work per frame.
struct MarqueeText: View {
    let text: String
    let font: Font
    /// Given explicitly: the scrolling copy is an image, which does not pick
    /// up the surrounding foreground style.
    var color: Color = .white

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @State private var textWidth = 0.0
    @State private var boxWidth = 0.0
    /// The text drawn once, at the screen's pixel density; only while it scrolls.
    @State private var image: CGImage?

    /// Space between the end of the text and the start of its copy.
    private static let gap = 48.0
    /// Scroll speed in points per second.
    private static let speed = 30.0
    /// Rest at the start of each round, in seconds.
    private static let pause = 2.5
    /// Width of the soft fade at the edges while scrolling.
    private static let fade = 12.0

    private var scrolls: Bool { !reduceMotion && boxWidth > 0 && textWidth > boxWidth + 0.5 }

    var body: some View {
        Text(text)
            .font(font)
            .foregroundStyle(color)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            // Hidden (but still sizing the row) while the scrolling copy shows.
            .opacity(scrolls && image != nil ? 0 : 1)
            .overlay {
                if scrolls, let image {
                    ScrollingImageView(
                        image: image,
                        scale: displayScale,
                        gap: Self.gap,
                        speed: Self.speed,
                        pause: Self.pause,
                        fade: Self.fade
                    )
                }
            }
            // The text's natural width, measured without affecting the layout.
            .background {
                Text(text).font(font).fixedSize().hidden()
                    .onGeometryChange(for: Double.self) { $0.size.width } action: { textWidth = $0 }
            }
            .onGeometryChange(for: Double.self) { $0.size.width } action: { boxWidth = $0 }
            // Drawn again when the song, the screen or the need changes.
            .task(id: ImageKey(text: text, scale: displayScale, scrolls: scrolls)) { renderImage() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private func renderImage() {
        guard scrolls else {
            image = nil
            return
        }
        let renderer = ImageRenderer(content: Text(text).font(font).foregroundStyle(color).fixedSize())
        renderer.scale = displayScale
        image = renderer.cgImage
    }

    private struct ImageKey: Equatable {
        let text: String
        let scale: Double
        let scrolls: Bool
    }
}

#Preview {
    VStack(spacing: 20) {
        MarqueeText(text: "Short title", font: .title2.weight(.semibold))
        MarqueeText(text: "A very long song title that does not fit into the window at all", font: .title2.weight(.semibold))
    }
    .frame(width: 284)
    .padding()
    .foregroundStyle(.white)
    .background(.black)
}
