import AppKit
import SwiftUI

/// Keeps the shared controls attached to native and external full-phone mirrors.
final class MirrorWindowControls {
    static let shared = MirrorWindowControls()

    private final class Session {
        weak var parent: NSWindow?
        var process: Process?
        var serial: String?
        var enabled = true
        let desktopMode: Bool
        let header: NSPanel
        let navigation: NSPanel
        var fittedSize: NSSize?
        var fittedHeaderHeight: CGFloat?
        var fittedNavigation: Bool?

        init(parent: NSWindow? = nil, process: Process? = nil, serial: String? = nil, desktopMode: Bool = false) {
            self.desktopMode = desktopMode
            self.parent = parent
            self.process = process
            self.serial = serial
            let width: CGFloat = desktopMode ? 560 : 320
            header = MirrorWindowControls.panel(
                HStack(spacing: 8) {
                    PhoneMirrorHeader(desktopMode: desktopMode, dragWindow: parent)
                    if let parent {
                        Button { parent.performClose(nil) } label: {
                            Image(systemName: "xmark.circle.fill")
                        }.buttonStyle(.plain).help("Close mirror").accessibilityLabel("Close mirror")
                    }
                }.padding(6).frame(width: width).fixedSize(horizontal: false, vertical: true), height: 48, width: width)
            header.title = "Mirror header controls"
            let handler: ((MirrorNavigationAction) -> Void)? = serial.map { target in
                { ADBConnector.performMirrorControl($0, serial: target) }
            }
            navigation = MirrorWindowControls.panel(
                MirrorNavigationBar(desktopMode: desktopMode, commandHandler: handler)
                    .frame(width: width),
                height: 44, width: width)
            if let parent {
                parent.addChildWindow(header, ordered: .above)
                parent.addChildWindow(navigation, ordered: .above)
            }
        }
        func close() {
            for panel in [header, navigation] {
                panel.parent?.removeChildWindow(panel)
                panel.orderOut(nil)
            }
        }
    }

    private var native: [Int: Session] = [:]
    private var external: [Int32: Session] = [:]
    private var timer: Timer?
    private var positioning = false

    private static func panel(_ view: some View, height: CGFloat, width: CGFloat = 320) -> NSPanel {
        let panel = MirrorControlsPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        // A fully clear borderless panel lets mouse events fall through its
        // empty pixels. Keep the entire panel available as a drag target.
        panel.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.02)
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.fullScreenAuxiliary]
        let host = NSHostingView(rootView: view)
        panel.contentView = host
        return panel
    }

    func updateNative(parent: NSWindow, isMirroring: Bool, showsControls: Bool, desktopMode: Bool = false) {
        let id = parent.windowNumber
        guard isMirroring else { removeNative(parent: parent); return }
        if native[id] == nil { native[id] = Session(parent: parent, desktopMode: desktopMode) }
        native[id]?.enabled = showsControls
        startTimer()
        refresh()
    }

    func removeNative(parent: NSWindow) {
        native.removeValue(forKey: parent.windowNumber)?.close()
        stopTimerIfEmpty()
    }

    func addExternal(process: Process, serial: String) {
        let id = process.processIdentifier
        guard process.isRunning else { return }
        external.removeValue(forKey: id)?.close()
        external[id] = Session(process: process, serial: serial)
        startTimer()
        refresh()
    }

    func removeExternal(processID: Int32) {
        external.removeValue(forKey: processID)?.close()
        stopTimerIfEmpty()
    }

    private func startTimer() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func stopTimerIfEmpty() {
        if native.isEmpty && external.isEmpty { timer?.invalidate(); timer = nil }
    }

    private func ownsKeyWindow(_ session: Session) -> Bool {
        var key = NSApp.keyWindow
        while let current = key {
            if current === session.header || current === session.navigation { return true }
            key = current.parent ?? current.sheetParent
        }
        return false
    }

    func refresh() {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ourPID = ProcessInfo.processInfo.processIdentifier
        let controlsEnabled = UserDefaults.standard.object(forKey: "showMirrorControls") as? Bool ?? true
        let navigationEnabled = UserDefaults.standard.object(forKey: "showEmbeddedMirrorNavigation") as? Bool ?? true
        for (id, session) in Array(native) {
            guard let parent = session.parent else { native.removeValue(forKey: id)?.close(); continue }
            // Floating mirrors remain visible when another application has focus.
            let active = !NSApp.isHidden && (parent.level >= .floating ||
                (frontPID == ourPID && (parent.isMainWindow || parent.isKeyWindow || ownsKeyWindow(session))))
            session.header.level = NSWindow.Level(rawValue: parent.level.rawValue + 1)
            session.navigation.level = session.header.level
            position(session, frame: parent.frame, visible: (UserDefaults.standard.object(forKey: (session.desktopMode ? MirrorProfile.desktop : .phone).controlsKey) as? Bool ?? true) && session.enabled && parent.isVisible && !parent.isMiniaturized && active,
                     navigationEnabled: UserDefaults.standard.object(forKey: (session.desktopMode ? MirrorProfile.desktop : .phone).navigationEnabledKey) as? Bool ?? true)
        }
        let windows = external.isEmpty ? [] : (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? [])
        for (pid, session) in Array(external) {
            guard session.process?.isRunning == true else { removeExternal(processID: pid); continue }
            guard let info = windows.first(where: {
                ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid &&
                    ($0[kCGWindowBounds as String] as? [String: Any]) != nil
            }), let bounds = info[kCGWindowBounds as String] as? [String: Any],
               let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else {
                session.header.orderOut(nil); session.navigation.orderOut(nil); continue
            }
            let top = NSScreen.screens.first?.frame.maxY ?? 0
            let frame = NSRect(x: rect.minX, y: top - rect.maxY, width: rect.width, height: rect.height)
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            let active = layer > 0 || frontPID == pid || (frontPID == ourPID && ownsKeyWindow(session))
            session.header.level = NSWindow.Level(rawValue: max(NSWindow.Level.floating.rawValue, layer + 1))
            session.navigation.level = session.header.level
            position(session, frame: frame, visible: controlsEnabled && active, navigationEnabled: navigationEnabled)
        }
        stopTimerIfEmpty()
    }

    private func position(_ session: Session, frame: NSRect, visible: Bool, navigationEnabled: Bool) {
        guard visible else { session.header.orderOut(nil); session.navigation.orderOut(nil); return }
        guard !positioning else { return }
        positioning = true
        defer { positioning = false }
        var frame = frame
        let screen = NSScreen.screens.max { first, second in
            let a = first.frame.intersection(frame), b = second.frame.intersection(frame)
            return a.width * a.height < b.width * b.height
        }?.visibleFrame ?? frame
        session.header.contentView?.layoutSubtreeIfNeeded()
        let headerHeight = min(300, max(36, session.header.contentView?.fittingSize.height ?? 36))
        // Reserve actual space outside the video instead of covering it when
        // the mirror is near the top or bottom of the display.
        if let parent = session.parent,
           session.fittedSize != frame.size || session.fittedHeaderHeight != headerHeight || session.fittedNavigation != navigationEnabled {
            let availableHeight = max(250, screen.height - headerHeight - 16 - (navigationEnabled ? 52 : 0))
            if frame.height > availableHeight {
                let scale = availableHeight / frame.height
                frame.size.width = max(parent.minSize.width, frame.width * scale)
                frame.size.height = availableHeight
            }
            frame.origin.y = max(screen.minY + (navigationEnabled ? 52 : 8),
                                 min(frame.origin.y, screen.maxY - headerHeight - 8 - frame.height))
            if parent.frame != frame { parent.setFrame(frame, display: true) }
            session.fittedSize = frame.size
            session.fittedHeaderHeight = headerHeight
            session.fittedNavigation = navigationEnabled
        }
        let width: CGFloat = session.desktopMode ? 560 : 320
        let x = max(screen.minX, min(frame.midX - width / 2, screen.maxX - width))
        let above = frame.maxY + 8
        let headerY = session.parent != nil ? above : min(above, screen.maxY - headerHeight)
        session.header.setFrame(NSRect(x: x, y: headerY, width: width, height: headerHeight), display: true)
        session.header.orderFront(nil)
        if navigationEnabled {
            let below = frame.minY - 52
            let y = session.parent != nil ? below : max(screen.minY, below)
            session.navigation.setFrame(NSRect(x: x, y: y, width: width, height: 44), display: true)
            session.navigation.orderFront(nil)
        } else { session.navigation.orderOut(nil) }
    }
}

private final class MirrorControlsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
