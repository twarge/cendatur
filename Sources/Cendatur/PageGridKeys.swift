import AppKit
import SwiftUI

/// ⌦ and ⎋ for the page grid. The Edit menu answers ⌫ for it, since SwiftUI
/// won't keep the grid focused long enough to hear keys itself — but a menu
/// item only takes one key, and a bare ⎋ never reaches the menu, so this
/// listens for those two in the window instead.
struct PageGridKeys: NSViewRepresentable {
    var canDelete: Bool
    var canDeselect: Bool
    var delete: () -> Void
    var deselect: () -> Void

    func makeNSView(context: Context) -> PageGridKeysView {
        let view = PageGridKeysView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: PageGridKeysView, context: Context) {
        view.keys = self
    }
}

final class PageGridKeysView: NSView {
    var keys: PageGridKeys?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return handled ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let keys, event.window === window,
            event.modifierFlags.isDisjoint(with: [.command, .option, .control, .shift])
        else { return false }
        if event.specialKey == .deleteForward, keys.canDelete {
            keys.delete()
        } else if event.charactersIgnoringModifiers == "\u{1b}", keys.canDeselect {
            keys.deselect()
        } else {
            return false
        }
        return true
    }

    // Only here to listen; clicks belong to the grid.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
