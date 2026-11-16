import AppKit

/// Playback keys while Aural's window is in front:
/// Space plays / pauses, ⌘→ goes to the next song, ⌘← to the previous one
/// (after 5 s it restarts the song, before that it goes back; see
/// `AppModel.previous`).
///
/// A local event monitor sees key presses before the window does. Keys are
/// left alone while a text field is being edited (search, setup), so Space
/// and ⌘← / ⌘→ still type and move the cursor there. SwiftUI's
/// `.keyboardShortcut(.space)` would take Space away from text fields.
@MainActor
final class KeyboardShortcuts {
    private let model: AppModel
    private var monitor: Any?

    init(model: AppModel) {
        self.model = model
    }

    func start() {
        guard monitor == nil else { return }
        // The closure runs on the main thread (local monitors always do), so
        // reaching into the main-actor model is safe. Only plain values go
        // in: `NSEvent` itself is not `Sendable`.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let handled = MainActor.assumeIsolated {
                self?.handle(keyCode: keyCode, modifiers: modifiers) ?? false
            }
            return handled ? nil : event // handled: the window never sees it
        }
    }

    /// True when the key was a playback shortcut and was acted on.
    private func handle(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Bool {
        guard model.phase == .player, model.playback.track != nil,
              let window = NSApp.keyWindow,
              !(window.firstResponder is NSText) // editing a text field
        else { return false }

        switch (keyCode, modifiers) {
        case (Self.space, []):
            model.togglePlayPause()
        case (Self.rightArrow, [.command]):
            model.next()
        case (Self.leftArrow, [.command]):
            model.previous()
        default:
            return false
        }
        return true
    }

    // Virtual key codes (layout-independent): Carbon's kVK_Space, kVK_LeftArrow, kVK_RightArrow.
    private static let space: UInt16 = 49
    private static let leftArrow: UInt16 = 123
    private static let rightArrow: UInt16 = 124
}
