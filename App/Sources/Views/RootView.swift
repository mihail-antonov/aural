import SwiftUI

/// The window: a fixed 320 × 576 pt portrait window with the cover-tinted
/// gradient as its background, showing the setup flow or the player pages.
struct RootView: View {
    @Environment(AppModel.self) private var model
    /// Height of the hidden title bar. macOS adds it on top of the content's
    /// size, so the content is made this much shorter (measured below; 32 pt
    /// on macOS 27, used until the first measurement).
    @State private var titleBarHeight = 32.0

    var body: some View {
        Group {
            switch model.phase {
            case .starting:
                ProgressView("Starting…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .setup:
                SetupView(setup: model.setup)
            case .player:
                MainView()
            }
        }
        .frame(width: Metrics.windowSize.width)
        .frame(maxHeight: .infinity)
        .onGeometryChange(for: Double.self) { $0.safeAreaInsets.top } action: { titleBarHeight = $0 }
        // The content runs under the (hidden) title bar, up to the window's top edge…
        .ignoresSafeArea()
        // …while the window is sized from this frame plus the title bar, so
        // the whole window is exactly `Metrics.windowSize` tall.
        .frame(height: Metrics.windowSize.height - titleBarHeight)
        .animation(.default, value: model.phase)
        // The toolbar exists on every screen, so the title bar keeps the same
        // height and the window buttons never move. Only the player has the
        // `…` menu; other screens hold an empty space of the same size.
        .toolbar {
            // Pushes the menu to the far right end of the toolbar.
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) {
                Group {
                    if model.phase == .player {
                        MoreMenu()
                    } else {
                        Color.clear.frame(width: 28, height: 28).accessibilityHidden(true)
                    }
                }
                .padding(.trailing, 8) // a little away from the window's right edge
            }
            // Just the icon: no glass circle behind it.
            .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(removing: .title)
        // No toolbar strip: the gradient shows through behind the menu.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // The gradient is the window's own background, so it fills every edge
        // of the window, including the area under the title bar. Until a cover
        // has loaded (e.g. during setup) it uses the design's dark slate.
        .containerBackground(for: .window) {
            Theme.background(for: model.coverColor)
                .animation(.smooth(duration: 0.6), value: model.coverColor)
        }
        // The background is always dark, so text and glass use their dark variants.
        .environment(\.colorScheme, .dark)
    }
}
