import AppKit
import SwiftUI

@main
struct AuralApp: App {
    // SwiftUI apps have no AppDelegate by default; this adaptor adds one so we
    // can run code at launch and delay quitting until Soloist has stopped.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Aural", id: "main") {
            RootView()
                .environment(appDelegate.model)
        }
        .windowResizability(.contentSize)
    }
}

/// Owns the app model and handles the app's lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await model.launch() }
    }

    /// Quitting waits until Soloist is stopped, so it never keeps running alone.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await model.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
