import AppKit
import SwiftUI

/// The phone-name view is the only draggable part of the controls.
struct MirrorNameDragLabel: NSViewRepresentable {
    let name: String
    let mirror: NSWindow
    var onMoved: () -> Void = {}
    func makeNSView(context: Context) -> MirrorDragView {
        let view = MirrorDragView()
        view.mirror = mirror
        view.onMoved = onMoved
        view.name = name
        view.toolTip = "Drag the phone name to move the mirror"
        return view
    }
    func updateNSView(_ view: MirrorDragView, context: Context) {
        view.mirror = mirror
        view.onMoved = onMoved
        view.name = name
        view.needsDisplay = true
    }
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: MirrorDragView, context: Context) -> CGSize? {
        CGSize(width: 140, height: 28)
    }
}

final class MirrorDragView: NSView {
    weak var mirror: NSWindow?
    var name = ""
    var onMoved: () -> Void = {}
    override var needsPanelToBecomeKey: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        let target = NSRect(x: bounds.minX, y: bounds.minY, width: min(140, bounds.width), height: bounds.height)
        return !isHiddenOrHasHiddenAncestor && target.contains(local) ? self : nil
    }
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.withAlphaComponent(0.15).setFill()
        bounds.fill()
        let text = NSAttributedString(string: name, attributes: [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ])
        text.draw(at: NSPoint(x: 4, y: max(0, (bounds.height - text.size().height) / 2)))
    }
    override func mouseDown(with event: NSEvent) {
        guard let mirror else { return }
        // Track only this dedicated drag surface. The original event belongs
        // to the floating panel, so handing it to another window's native
        // drag API can fail. Move the mirror explicitly in screen coordinates.
        let start = NSEvent.mouseLocation
        let origin = mirror.frame.origin
        NSCursor.closedHand.push()
        defer { NSCursor.pop() }
        while true {
            guard let next = NSApp.nextEvent(matching: [.leftMouseDragged, .leftMouseUp],
                                            until: Date(timeIntervalSinceNow: 0.1),
                                            inMode: .eventTracking, dequeue: true) else {
                if NSEvent.pressedMouseButtons & 1 == 0 { break }
                continue
            }
            let point = NSEvent.mouseLocation
            mirror.setFrameOrigin(NSPoint(x: origin.x + point.x - start.x, y: origin.y + point.y - start.y))
            onMoved()
            if next.type == .leftMouseUp { break }
        }
    }
}
