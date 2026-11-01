import AppKit
import ApplicationServices

/// Where live activities can go without covering menu bar items.
enum LivePlacement: Equatable {
    case split        // one wing on each side of the notch
    case right        // everything right of the notch
    case left         // everything left of the notch
}

/// Measures free menu bar space beside the notch through Accessibility: the frontmost app's
/// menus (left of the notch, or past it when macOS moves overflow menus right) and every app's
/// menu bar extras (status icons, right side). Menu bar items aren't separate windows on current
/// macOS, so there's no permission-free way to see them; without Accessibility both sides count
/// as free and the wings may cover items.
final class MenuBarSpace {
    private let screen: NSScreen
    private let notchWidth: CGFloat
    /// Cached free widths; refreshed on app switches and when an activity appears.
    private(set) var leftFree: CGFloat = .infinity
    private(set) var rightFree: CGFloat = .infinity
    private static let margin: CGFloat = 8
    private let queue = DispatchQueue(label: "MenuBarSpace")   // AX queries to many apps are slow
    private var measuring = false

    init(screen: NSScreen, notchWidth: CGFloat) {
        self.screen = screen
        self.notchWidth = notchWidth
    }

    var canMeasure: Bool { AXIsProcessTrusted() }

    func placement(for activity: LiveActivity) -> LivePlacement? {
        let w = activity.wing + Self.margin
        if leftFree >= w && rightFree >= w { return .split }
        if rightFree >= 2 * w { return .right }
        if leftFree >= 2 * w { return .left }
        return nil
    }

    /// Re-measures in the background, then calls `done` on the main queue.
    func measure(_ done: @escaping () -> Void) {
        guard canMeasure else {
            leftFree = .infinity
            rightFree = .infinity
            return done()
        }
        guard !measuring else { return }
        measuring = true
        // Screen geometry is read here on the main thread; AX work happens on the queue.
        let frame = screen.frame
        let top = (NSScreen.screens.first?.frame.height ?? frame.height) - frame.maxY   // global top-left coords
        let barHeight = max(screen.safeAreaInsets.top, 24)
        let notchWidth = notchWidth
        let front = NSWorkspace.shared.frontmostApplication
        let apps = NSWorkspace.shared.runningApplications
        queue.async { [weak self] in
            let (left, right) = Self.freeSpace(frame: frame, top: top, barHeight: barHeight, notchWidth: notchWidth,
                                                front: front, apps: apps)
            DispatchQueue.main.async {
                guard let self else { return }
                self.leftFree = left
                self.rightFree = right
                self.measuring = false
                done()
            }
        }
    }

    private static func freeSpace(frame: CGRect, top: CGFloat, barHeight: CGFloat, notchWidth: CGFloat,
                                  front: NSRunningApplication?, apps: [NSRunningApplication]) -> (CGFloat, CGFloat) {
        let inBar = { (r: CGRect) in r.midY > top && r.midY < top + barHeight && r.maxX > frame.minX && r.minX < frame.maxX }

        var leftEdge = frame.minX     // rightmost occupied x left of the notch
        var rightEdge = frame.maxX    // leftmost occupied x right of the notch
        var frames = menuFrames(of: front, attribute: kAXMenuBarAttribute)
        for app in apps {
            frames += menuFrames(of: app, attribute: "AXExtrasMenuBar")
        }
        for r in frames where inBar(r) {
            if r.midX < frame.midX { leftEdge = max(leftEdge, r.maxX) } else { rightEdge = min(rightEdge, r.minX) }
        }
        return (max(frame.midX - notchWidth / 2 - leftEdge, 0), max(rightEdge - (frame.midX + notchWidth / 2), 0))
    }

    /// Frames of the items in an app's menu bar (`AXMenuBar`) or status icons (`AXExtrasMenuBar`).
    private static func menuFrames(of app: NSRunningApplication?, attribute: String) -> [CGRect] {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return [] }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.05)   // don't hang on unresponsive apps
        var bar: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &bar) == .success,
              let bar, CFGetTypeID(bar) == AXUIElementGetTypeID() else { return [] }
        var children: CFTypeRef?
        guard AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &children) == .success,
              let items = children as? [AXUIElement] else { return [] }
        return items.compactMap { item in
            var pos: CFTypeRef?, size: CFTypeRef?
            guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &pos) == .success,
                  AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success else { return nil }
            var p = CGPoint.zero, s = CGSize.zero
            AXValueGetValue(pos as! AXValue, .cgPoint, &p)
            AXValueGetValue(size as! AXValue, .cgSize, &s)
            return s.width > 0 ? CGRect(origin: p, size: s) : nil
        }
    }
}
