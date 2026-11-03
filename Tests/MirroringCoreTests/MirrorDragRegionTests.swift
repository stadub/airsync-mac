import AppKit
import XCTest
@testable import MirroringUI

final class MirrorDragRegionTests: XCTestCase {
    @MainActor
    func testOnlyNameReceivesDragHitsAndButtonRemainsClickable() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 40))
        let drag = MirrorDragView(frame: NSRect(x: 10, y: 6, width: 200, height: 28))
        let button = NSButton(frame: NSRect(x: 220, y: 6, width: 80, height: 28))
        container.addSubview(drag)
        container.addSubview(button)
        XCTAssertTrue(container.hitTest(NSPoint(x: 30, y: 20)) === drag)
        XCTAssertNil(drag.hitTest(NSPoint(x: 160, y: 20)))
        XCTAssertTrue(container.hitTest(NSPoint(x: 250, y: 20)) === button)
        drag.isHidden = true
        XCTAssertNil(drag.hitTest(NSPoint(x: 30, y: 20)))
    }
}
