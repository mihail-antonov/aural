import AppKit
import SwiftUI

extension View {
    /// Calls `action` whenever this view's window becomes visible or invisible.
    /// The window counts as invisible while it is fully covered by other
    /// windows, minimized, hidden with the app or on another Space, so
    /// animations nobody can see can pause and save CPU.
    func onWindowVisibilityChange(_ action: @escaping (Bool) -> Void) -> some View {
        background(WindowVisibilityReader(onChange: action))
    }
}

/// SwiftUI does not tell a view which window it is in, nor whether that
/// window can be seen. An empty AppKit view placed behind the content can do
/// both: AppKit tells it when it joins a window, and macOS posts an
/// "occlusion state" notification whenever that window's visibility changes.
private struct WindowVisibilityReader: NSViewRepresentable {
    let onChange: (Bool) -> Void

    func makeNSView(context: Context) -> ReaderView { ReaderView() }

    func updateNSView(_ view: ReaderView, context: Context) {
        view.onChange = onChange
    }

    final class ReaderView: NSView {
        var onChange: ((Bool) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // Selector-based observers are removed by the system when the
            // view goes away, so no cleanup is needed in `deinit`.
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
            guard let window else { return }
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(occlusionChanged),
                name: NSWindow.didChangeOcclusionStateNotification,
                object: window
            )
            report()
        }

        @objc private func occlusionChanged(_ notification: Notification) {
            report()
        }

        private func report() {
            let isVisible = window?.occlusionState.contains(.visible) ?? false
            // Reported on the next turn of the main loop: this can run while
            // SwiftUI is still updating its views, and changing view state in
            // the middle of that update is not allowed.
            Task { @MainActor [onChange] in onChange?(isVisible) }
        }
    }
}
