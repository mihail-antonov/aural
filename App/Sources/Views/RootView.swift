import SwiftUI

/// Switches between the setup flow and the player.
struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            switch model.phase {
            case .starting:
                ProgressView("Starting…")
                    .frame(width: 340, height: 360)
            case .setup:
                SetupView(setup: model.setup)
            case .player:
                MainView()
            }
        }
        .animation(.default, value: model.phase)
    }
}
