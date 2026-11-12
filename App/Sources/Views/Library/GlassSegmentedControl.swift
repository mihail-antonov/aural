import SwiftUI

/// Tabs inside a page (Playlists / Liked / Albums), after docs/navigation.png:
/// a recessed track with text segments and a raised Liquid Glass thumb on the
/// selected one, a little taller than the track. The thumb slides with a small
/// bounce and reacts to the pointer (`.interactive()`).
///
/// Built from Apple's glass API (`glassEffect`) because SwiftUI's segmented
/// `Picker` keeps the classic macOS look inside window content. The glass
/// follows the system's Liquid Glass and accessibility settings.
struct GlassSegmentedControl<Value: Hashable>: View {
    @Binding var selection: Value
    let items: [(value: Value, title: String)]

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static var trackHeight: Double { 30 }
    /// How far the thumb stands out of the track on each side.
    private static var overhang: Double { 2 }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items, id: \.value) { item in
                segment(item.value, title: item.title)
            }
        }
        .background(Capsule().fill(.black.opacity(0.2)))
        .padding(Self.overhang) // room for the overhanging thumb
    }

    private func segment(_ value: Value, title: String) -> some View {
        let isSelected = selection == value
        return Button {
            // No bounce with Reduce Motion.
            withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .bouncy(duration: 0.35)) { selection = value }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: Self.trackHeight)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.clear)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            .padding(-Self.overhang)
                            .matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
        }
        .buttonStyle(SegmentButtonStyle(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Selected segment: full white. Others: dimmed, brighter on hover.
private struct SegmentButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SegmentButtonBody(configuration: configuration, isSelected: isSelected)
    }
}

private struct SegmentButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .foregroundStyle(.white.opacity(isSelected ? 1 : isHovered ? 0.8 : 0.55))
            .contentShape(.capsule)
            .onHover { isHovered = $0 }
            .animation(Theme.hoverAnimation, value: isHovered)
    }
}
