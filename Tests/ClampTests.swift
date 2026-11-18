import CoreGraphics
import Testing
@testable import Dockinator

// A laptop at the origin with a monitor below its right half.
let laptop = CGRect(x: 0, y: 0, width: 1800, height: 1169)
let below = CGRect(x: 900, y: 1169, width: 2560, height: 1440)
func onScreen(_ p: CGPoint) -> Bool { [laptop, below].contains { $0.contains(p) } }

@Test func pointerAtExposedBottomEdgeIsPushedUp() {
    #expect(clampedPointer(CGPoint(x: 100, y: 1168), in: laptop, isOnScreen: onScreen) == CGPoint(x: 100, y: 1169 - 2 - edgeMargin))
}

@Test func pointerAwayFromEdgeIsLeftAlone() {
    #expect(clampedPointer(CGPoint(x: 100, y: 1000), in: laptop, isOnScreen: onScreen) == nil)
}

@Test func edgeSharedWithDisplayBelowIsLeftAlone() {
    // The pointer has to be able to cross into the monitor below.
    #expect(clampedPointer(CGPoint(x: 1000, y: 1168), in: laptop, isOnScreen: onScreen) == nil)
}
