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
        // No title bar: the player's background runs under the window buttons.
        .windowStyle(.hiddenTitleBar)
    }
}

/// Owns the app model and handles the app's lifecycle.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        // `AsyncImage` uses the shared URL cache, which by default also keeps
        // downloaded images in memory. Keep them on disk only (capped).
        URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 20 * 1024 * 1024)
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
