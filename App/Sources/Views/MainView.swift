import SwiftUI

/// The main window: the player or the library, on the cover-tinted background.
struct MainView: View {
    @Environment(AppModel.self) private var model
    /// System setting (Accessibility → Display → Reduce motion): pages
    /// cross-fade instead of sliding.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Height of the hidden title bar. macOS adds it on top of the content's
    /// size, so the content is made this much shorter (measured below; 32 pt
    /// on macOS 27, used until the first measurement).
    @State private var titleBarHeight = 32.0

    var body: some View {
        ZStack {
            // Library and search slide in from the right over the player's place;
            // the player slides back in from the left.
            switch model.page {
            case .player:
                PlayerView() // positions its rows from the window top itself
                    .transition(pageTransition(from: .leading))
            case .library:
                LibraryPage()
                    .padding(.top, Metrics.contentTop)
                    .transition(pageTransition(from: .trailing))
            case .search:
                SearchPage()
                    .padding(.top, Metrics.contentTop)
                    .transition(pageTransition(from: .trailing))
            }
        }
        .frame(width: Metrics.windowSize.width)
        .frame(maxHeight: .infinity)
        .clipped() // sliding pages stay inside the window
        .onGeometryChange(for: Double.self) { $0.safeAreaInsets.top } action: { titleBarHeight = $0 }
        // The pages run under the (hidden) title bar, up to the window's top edge…
        .ignoresSafeArea()
        // …while the window is sized from this frame plus the title bar, so
        // the whole window is exactly `Metrics.windowSize` tall.
        .frame(height: Metrics.windowSize.height - titleBarHeight)
        .animation(.smooth(duration: 0.3), value: model.page)
        .toolbar {
            // Pushes the menu to the far right end of the toolbar.
            ToolbarSpacer(.flexible)
            ToolbarItem(placement: .primaryAction) { MoreMenu() }
                // Just the icon: no glass circle behind it.
                .sharedBackgroundVisibility(.hidden)
        }
        .toolbar(removing: .title)
        // No toolbar strip: the gradient shows through behind the menu.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // The gradient is the window's own background, so it fills every edge
        // of the window, including the area under the title bar.
        .containerBackground(for: .window) {
            Theme.background(for: model.coverColor)
                .animation(.smooth(duration: 0.6), value: model.coverColor)
        }
        // The background is always dark, so text and glass use their dark variants.
        .environment(\.colorScheme, .dark)
    }

    private func pageTransition(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
