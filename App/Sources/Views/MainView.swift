import SwiftUI

/// The player, library and search pages. The window's size and background
/// come from `RootView`.
struct MainView: View {
    @Environment(AppModel.self) private var model
    /// System setting (Accessibility → Display → Reduce motion): pages
    /// cross-fade instead of sliding.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
        .clipped() // sliding pages stay inside the window
        .animation(.smooth(duration: 0.3), value: model.page)
    }

    private func pageTransition(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}
