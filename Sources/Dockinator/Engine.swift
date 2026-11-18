// The Dock-locking mechanics. No UI here.
//
// macOS moves the Dock to a display when the pointer pushes against that
// display's bottom edge. We keep the pointer one pixel above the exposed bottom
// edge of every blocked display, so that push never happens:
//   - with Accessibility: an event tap clamps each mouse move before the Dock sees it;
//   - without: a 240 Hz poll warps the pointer back (warping needs no permission).
// With Accessibility we also read which display the Dock is on, so the panel can
// say when it ended up somewhere blocked. Moving it back is left to the user:
// macOS ignores synthetic pointer pushes for Dock moves.
//
// Only a bottom Dock can move between displays, so left/right need no locking.

import Cocoa
import ServiceManagement

enum Edge: String, CaseIterable, Identifiable {
    case bottom, left, right
    var id: String { rawValue }
}

/// Pixels kept free above the bottom edge of blocked displays. Raise if the Dock still slips through.
let edgeMargin: CGFloat = 1

func activeDisplays() -> [CGDirectDisplayID] {
    var n: UInt32 = 0
    CGGetActiveDisplayList(0, nil, &n)
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
    CGGetActiveDisplayList(n, &ids, &n)
    return Array(ids.prefix(Int(n)))
}

/// Stable across reboots and reconnects, unlike CGDirectDisplayID.
func displayUUID(_ d: CGDirectDisplayID) -> String? {
    guard let u = CGDisplayCreateUUIDFromDisplayID(d)?.takeRetainedValue() else { return nil }
    return CFUUIDCreateString(nil, u) as String
}

func displayName(_ id: CGDirectDisplayID) -> String {
    NSScreen.screens.first {
        ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == id
    }?.localizedName ?? "Display \(id)"
}

func cursorLocation() -> CGPoint? { CGEvent(source: nil)?.location }

/// Where to put the pointer so it stays off the bottom edge of display `b`, or nil when no move is needed.
/// `isOnScreen` tells whether a point lies on any display: an edge shared with a display below is left alone.
func clampedPointer(_ p: CGPoint, in b: CGRect, isOnScreen: (CGPoint) -> Bool) -> CGPoint? {
    guard p.y >= b.maxY - 1 - edgeMargin, !isOnScreen(CGPoint(x: p.x, y: b.maxY + 1)) else { return nil }
    return CGPoint(x: p.x, y: b.maxY - 2 - edgeMargin)
}

/// Display holding the Dock's item list, read via Accessibility. Nil without permission.
func dockDisplay() -> CGDirectDisplayID? {
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
    else { return nil }
    var kids: CFTypeRef?
    guard AXUIElementCopyAttributeValue(AXUIElementCreateApplication(pid), kAXChildrenAttribute as CFString, &kids) == .success,
          let list = (kids as? [AXUIElement])?.first else { return nil }
    var posRef: CFTypeRef?, sizeRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(list, kAXPositionAttribute as CFString, &posRef) == .success,
          AXUIElementCopyAttributeValue(list, kAXSizeAttribute as CFString, &sizeRef) == .success
    else { return nil }
    var pos = CGPoint.zero, size = CGSize.zero
    AXValueGetValue(posRef as! AXValue, .cgPoint, &pos)
    AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
    let mid = CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2)
    // An auto-hidden Dock sits off-screen and reads as nil, so it is never pulled back.
    return activeDisplays().first { CGDisplayBounds($0).contains(mid) }
}

func dockOrientation() -> Edge {
    Edge(rawValue: UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") ?? "") ?? .bottom
}

/// Writes the Dock preference and restarts the Dock, only when it differs.
func setDockOrientation(_ edge: Edge) {
    guard dockOrientation() != edge else { return }
    for args in [["defaults", "write", "com.apple.dock", "orientation", "-string", edge.rawValue], ["killall", "Dock"]] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        p.arguments = args
        try? p.run()
        p.waitUntilExit()
    }
}

// MARK: locker

final class Locker {
    enum Method { case off, eventTap, polling }

    var enabled = true
    var edge: Edge = .bottom
    var home: CGDirectDisplayID?
    var allowed: Set<CGDirectDisplayID> = []
    private(set) var method: Method = .off

    private var tap: CFMachPort?
    private var poll: Timer?

    var active: Bool { enabled && edge == .bottom && home != nil }

    func isBlocked(_ d: CGDirectDisplayID) -> Bool { d != home && !allowed.contains(d) }

    /// The clamped pointer for `p`, or nil when `p` is fine.
    func clamp(_ p: CGPoint) -> CGPoint? {
        guard active else { return nil }
        let ds = activeDisplays()
        guard let d = ds.first(where: { CGDisplayBounds($0).contains(p) }), isBlocked(d) else { return nil }
        return clampedPointer(p, in: CGDisplayBounds(d)) { pt in ds.contains { CGDisplayBounds($0).contains(pt) } }
    }

    /// Picks the event tap when Accessibility allows it, polling otherwise. Safe to call repeatedly.
    func updateMethod() {
        if tap == nil, AXIsProcessTrusted() { installTap() }
        if let tap, !CGEvent.tapIsEnabled(tap: tap) { CGEvent.tapEnable(tap: tap, enable: true) }
        if tap != nil {
            poll?.invalidate(); poll = nil
            method = .eventTap
        } else {
            if poll == nil {
                poll = Timer(timeInterval: 1.0 / 240, repeats: true) { [unowned self] _ in
                    guard let p = cursorLocation(), let q = clamp(p) else { return }
                    CGWarpMouseCursorPosition(q)
                    CGAssociateMouseAndMouseCursorPosition(1)  // skip the post-warp input freeze
                }
                RunLoop.main.add(poll!, forMode: .common)
            }
            method = .polling
        }
    }

    private func installTap() {
        let mask = [CGEventType.mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged]
            .reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let callback: CGEventTapCallBack = { _, type, event, info in
            let me = Unmanaged<Locker>.fromOpaque(info!).takeUnretainedValue()
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let tap = me.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            } else if let q = me.clamp(event.location) {
                event.location = q
                event.setIntegerValueField(.mouseEventDeltaY, value: 0)
                CGWarpMouseCursorPosition(q)
            }
            return Unmanaged.passUnretained(event)
        }
        guard let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: callback,
                                        userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        tap = t
        CFRunLoopAddSource(CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, t, 0), .commonModes)
    }
}

// MARK: setup checks

enum Checks {
    static var accessibility: Bool { AXIsProcessTrusted() }
    /// The Dock only moves between displays when each display has its own Spaces.
    static var separateSpaces: Bool { !(UserDefaults(suiteName: "com.apple.spaces")?.bool(forKey: "spans-displays") ?? false) }
    static var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    static func requestAccessibility() {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        openSettings("com.apple.preference.security?Privacy_Accessibility")
    }

    static func toggleLaunchAtLogin() throws {
        if launchAtLogin { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
    }

    static func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:\(pane)")!)
    }
}
