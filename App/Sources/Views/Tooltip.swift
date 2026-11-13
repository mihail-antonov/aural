import AppKit
import SwiftUI

// Spotify-style tooltips: a small dark label that appears above an icon
// shortly after the pointer rests on it. macOS's own tooltips (`.help`) show
// near the pointer after about a second; this is a deliberate exception
// (agreed with the owner) to "system controls only".
//
// How it works: buttons report their hover and their frame to one shared
// `TooltipCenter`; `RootView` draws the label in a layer above the whole
// window, so it is never clipped by, or hidden under, neighbouring views.

extension View {
    /// Shows `text` above this view (below it near the window's top) when
    /// the pointer rests on it.
    func tooltip(_ text: String) -> some View {
        modifier(TooltipModifier(text: text))
    }
}

extension EnvironmentValues {
    /// Set by `RootView`; nil in previews, where tooltips simply don't show.
    @Entry var tooltipCenter: TooltipCenter?
}

/// The one tooltip shown at a time.
@MainActor
@Observable
final class TooltipCenter {
    struct Tip: Equatable {
        let owner: UUID
        let text: String
        /// The hovered view's frame in window coordinates.
        let anchor: CGRect
    }

    private(set) var tip: Tip?

    @ObservationIgnored private var showTask: Task<Void, Never>?
    /// The view whose tip `showTask` will show.
    @ObservationIgnored private var pendingOwner: UUID?
    @ObservationIgnored private var eventMonitor: Any?

    /// Every icon waits this long, also when moving from one to the next.
    private static let delay: Duration = .milliseconds(450)

    init() {
        // Any click, scroll or key press hides the tip right away. A local
        // monitor sees the app's events before the views do, and passes
        // them on unchanged.
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            // AppKit calls this on the main thread.
            MainActor.assumeIsolated { self?.hide() }
            return event
        }
    }

    func hover(_ owner: UUID, text: String, anchor: CGRect, isHovering: Bool) {
        guard isHovering else {
            // Only this view's own tip or pending tip: when moving between
            // icons, the old icon's "leave" can arrive after the new one's
            // "enter" and must not cancel the new one.
            if pendingOwner == owner { cancelPending() }
            if tip?.owner == owner { tip = nil }
            return
        }
        // Every icon waits the full delay, also right after another one's tip.
        cancelPending()
        tip = nil
        let next = Tip(owner: owner, text: text, anchor: anchor)
        pendingOwner = owner
        showTask = Task { [weak self] in
            try? await Task.sleep(for: Self.delay)
            guard !Task.isCancelled, let self else { return }
            tip = next
            pendingOwner = nil
        }
    }

    /// Updates the text of a tip that is showing (e.g. "Shuffle: on" → "off").
    func update(_ owner: UUID, text: String) {
        guard let tip, tip.owner == owner, tip.text != text else { return }
        self.tip = Tip(owner: owner, text: text, anchor: tip.anchor)
    }

    func hide(_ owner: UUID? = nil) {
        if let owner {
            if pendingOwner == owner { cancelPending() }
            if tip?.owner == owner { tip = nil }
            return
        }
        cancelPending()
        tip = nil
    }

    private func cancelPending() {
        showTask?.cancel()
        showTask = nil
        pendingOwner = nil
    }
}

private struct TooltipModifier: ViewModifier {
    let text: String
    @Environment(\.tooltipCenter) private var center
    @State private var id = UUID()
    @State private var frame = CGRect.zero

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onHover { center?.hover(id, text: text, anchor: frame, isHovering: $0) }
            .onChange(of: text) { center?.update(id, text: text) }
            .onDisappear { center?.hide(id) }
    }
}

/// Draws the current tip above the whole window. Placed by `RootView`.
struct TooltipLayer: View {
    let center: TooltipCenter
    /// Measured size of the label, per tip (it is placed once known).
    @State private var measured: (tip: TooltipCenter.Tip, size: CGSize)?

    /// Between the hovered view's frame and the label.
    private static let gap = 8.0
    /// The label keeps this distance from the window's edges.
    private static let margin = 8.0

    var body: some View {
        GeometryReader { proxy in
            if let tip = center.tip {
                let size = measured?.tip == tip ? measured?.size : nil
                TooltipBubble(text: tip.text)
                    .fixedSize()
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { measured = (tip, $0) }
                    .position(position(for: tip, size: size ?? .zero, in: proxy.frame(in: .global)))
                    // Invisible for the one layout pass before its size is known.
                    .opacity(size == nil ? 0 : 1)
                    .id(tip.owner)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: center.tip?.owner)
        .allowsHitTesting(false)
        .accessibilityHidden(true) // the buttons have the same text as their label
    }

    /// Centered above the anchor, or below it if there is no room above;
    /// kept inside the window horizontally.
    private func position(for tip: TooltipCenter.Tip, size: CGSize, in layer: CGRect) -> CGPoint {
        let anchor = tip.anchor.offsetBy(dx: -layer.minX, dy: -layer.minY)
        let halfWidth = size.width / 2
        let x = min(max(anchor.midX, halfWidth + Self.margin), layer.width - halfWidth - Self.margin)
        let above = anchor.minY - Self.gap - size.height / 2
        let y = above - size.height / 2 >= Self.margin ? above : anchor.maxY + Self.gap + size.height / 2
        return CGPoint(x: x, y: y)
    }
}

/// Dark rounded label with a soft shadow, like Spotify's.
private struct TooltipBubble: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Color(white: 0.16), in: .rect(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(0.06)))
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
    }
}
