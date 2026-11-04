import AppKit
import SwiftUI

/// Reports the panel's window once SwiftUI has put the content into one.
///
/// `MenuBarExtra` keeps its content view alive after the panel closes, so
/// neither `onAppear` nor `onDisappear` ever runs again: a view's lifecycle
/// cannot say whether the panel is open. The window can — which is why the
/// store keeps the window and watches it instead.
struct PanelWindowProbe: NSViewRepresentable {
    let report: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        Probe(report: report)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        nonisolated(unsafe) let report: (NSWindow?) -> Void

        init(report: @escaping (NSWindow?) -> Void) {
            self.report = report
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report(window)
        }
    }
}
