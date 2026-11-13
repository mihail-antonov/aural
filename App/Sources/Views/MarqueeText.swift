import SwiftUI

/// One line of text that, when it is too long to fit, scrolls sideways to
/// show all of it, like Spotify's song titles: it rests for a moment, glides
/// left until a second copy has taken the first one's place, and starts over
/// (the two copies make the restart invisible). Text that fits is just
/// centered. With Reduce Motion it does not move and ends with "…" instead.
///
/// SwiftUI has no marquee, so this moves two copies of the text with an
/// offset animation. Only overflowing text animates, and the animation is a
/// plain linear offset, which the system renders cheaply.
struct MarqueeText: View {
    let text: String
    let font: Font

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var textWidth = 0.0
    @State private var boxWidth = 0.0
    @State private var offset = 0.0

    /// Space between the end of the text and the start of its copy.
    private static let gap = 48.0
    /// Scroll speed in points per second.
    private static let speed = 30.0
    /// Rest at the start of each round.
    private static let pause: Duration = .seconds(2.5)
    /// Width of the soft fade at the edges while scrolling.
    private static let fade = 12.0

    private var scrolls: Bool { !reduceMotion && boxWidth > 0 && textWidth > boxWidth + 0.5 }

    var body: some View {
        Text(text)
            .font(font)
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            // Hidden (but still sizing the row) while the scrolling copy shows.
            .opacity(scrolls ? 0 : 1)
            .overlay(alignment: .leading) {
                if scrolls { scrollingText }
            }
            // The text's natural width, measured without affecting the layout.
            .background {
                Text(text).font(font).fixedSize().hidden()
                    .onGeometryChange(for: Double.self) { $0.size.width } action: { textWidth = $0 }
            }
            .onGeometryChange(for: Double.self) { $0.size.width } action: { boxWidth = $0 }
            // Restarts from the beginning when the song or the space changes.
            .task(id: Restart(text: text, scrolls: scrolls, textWidth: textWidth)) { await scrollLoop() }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }

    private var scrollingText: some View {
        HStack(spacing: Self.gap) {
            Text(text)
            Text(text)
        }
        .font(font)
        .fixedSize()
        .offset(x: offset)
        .frame(width: boxWidth, alignment: .leading)
        .clipped()
        .mask {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: Self.fade / max(boxWidth, 1)),
                    .init(color: .black, location: 1 - Self.fade / max(boxWidth, 1)),
                    .init(color: .clear, location: 1),
                ],
                startPoint: .leading, endPoint: .trailing
            )
        }
    }

    private func scrollLoop() async {
        setOffset(0)
        guard scrolls else { return }
        let distance = textWidth + Self.gap
        let duration = distance / Self.speed
        while !Task.isCancelled {
            try? await Task.sleep(for: Self.pause)
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: duration)) { offset = -distance }
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            // The copy now sits exactly where the text started: jump back unseen.
            setOffset(0)
        }
    }

    private func setOffset(_ value: Double) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { offset = value }
    }

    private struct Restart: Equatable {
        let text: String
        let scrolls: Bool
        let textWidth: Double
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
