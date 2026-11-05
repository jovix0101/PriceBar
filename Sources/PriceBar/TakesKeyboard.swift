import AppKit
import SwiftUI

extension View {
    /// Makes the window this view is shown in the key window as soon as it is
    /// on screen, then calls `then` — where the view puts the focus in its
    /// field.
    ///
    /// A popover opened from the menu bar does not take the keyboard by
    /// itself. Activating the app hands it back to the window that last had
    /// it — the settings window, with the proxy address in it — so what was
    /// typed into the add-a-coin field went to the proxy address, or, with
    /// the settings closed, to no field at all. Asked for here, once the
    /// activation has settled, the keyboard comes to the popover in front.
    func takesKeyboard(then: @escaping () -> Void = {}) -> some View {
        background(KeyWindowMaker(then: then))
    }
}

private struct KeyWindowMaker: NSViewRepresentable {
    let then: () -> Void

    func makeNSView(context: Context) -> MakerView {
        let view = MakerView()
        view.then = then
        return view
    }

    func updateNSView(_ view: MakerView, context: Context) {
        view.then = then
    }

    final class MakerView: NSView {
        var then: () -> Void = {}

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else { return }
            // The next turn of the run loop: the popover is still being put on
            // screen now, and the app's activation still under way.
            DispatchQueue.main.async { [weak self] in
                guard let self, let window = self.window else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKey()
                self.then()
            }
        }
    }
}
