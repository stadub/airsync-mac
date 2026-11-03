import AppKit
import SwiftUI

/// Editors use a normal window, rather than a sheet attached to a 44-point panel.
final class MirrorLayoutEditorWindow {
    static let shared = MirrorLayoutEditorWindow()
    private var windows: [String: NSWindow] = [:]
    func showNavigation(desktopMode: Bool) { show(desktopMode: desktopMode, navigation: true) }
    func showHeader(desktopMode: Bool) { show(desktopMode: desktopMode, navigation: false) }
    private func show(desktopMode: Bool, navigation: Bool) {
        let key = "\(desktopMode)-\(navigation)"
        if let existing = windows[key] { existing.makeKeyAndOrderFront(nil); return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 410, height: navigation ? 520 : 490),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = navigation ? "Navigation buttons" : "Header buttons"
        window.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 3)
        let done = { [weak self, weak window] in window?.close(); self?.windows.removeValue(forKey: key) }
        if navigation {
            window.contentView = NSHostingView(rootView: MirrorNavigationEditor(desktopMode: desktopMode, onDone: done))
        } else {
            window.contentView = NSHostingView(rootView: MirrorHeaderEditor(desktopMode: desktopMode, onDone: done))
        }
        windows[key] = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
