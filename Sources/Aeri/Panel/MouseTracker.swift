import AppKit
import SwiftUI

/// Watches the mouse globally. The panel only takes clicks while the cursor is over
/// the visible notch shape, so menu bar items around it stay clickable.
/// Also drives hover-to-expand, since SwiftUI's onHover can't fire while events pass through.
/// Global monitors stop seeing mouse-dragged events once a drag session starts in another app,
/// so while the button is held we poll the cursor; that lets files dragged from Finder open the notch.
final class MouseTracker {
    private let panel: NSPanel
    private let state: NotchState
    private let notchSize: CGSize
    private var monitors: [Any] = []
    private var dragPoll: Timer?
    private var dragChangeCount = 0

    init(panel: NSPanel, state: NotchState, notchSize: CGSize) {
        self.panel = panel
        self.state = state
        self.notchSize = notchSize
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in self?.update() }) {
            monitors.append(g)
        }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in self?.update(); return e }) {
            monitors.append(l)
        }
        if let d = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in self?.startDragPoll() }) {
            monitors.append(d)
        }
        if let d = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] e in self?.startDragPoll(); return e }) {
            monitors.append(d)
        }
    }

    deinit {
        monitors.forEach(NSEvent.removeMonitor)
        dragPoll?.invalidate()
    }

    private func startDragPoll() {
        dragChangeCount = NSPasteboard(name: .drag).changeCount
        dragPoll?.invalidate()
        dragPoll = .scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] t in
            guard let self else { return t.invalidate() }
            if NSEvent.pressedMouseButtons & 1 == 0 {
                t.invalidate()
                self.dragPoll = nil
            }
            self.update()
        }
    }

    /// A new drag began since the button went down (the drag pasteboard changed).
    private var isDragging: Bool {
        dragPoll != nil && NSPasteboard(name: .drag).changeCount != dragChangeCount
    }

    /// Screen rect of the shape in its current state (matches NotchView's frame).
    private func shapeRect(expanded: Bool) -> NSRect {
        let size = expanded ? NotchView.expandedSize : notchSize
        let f = panel.frame
        return NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                      width: size.width, height: size.height)
    }

    private func update() {
        guard !state.holdOpen else { return }
        let p = NSEvent.mouseLocation
        // Small hit slop when collapsed so the notch is easy to reach from the top edge.
        let inside = shapeRect(expanded: state.expanded).insetBy(dx: state.expanded ? 0 : -4, dy: -1).contains(p)
        panel.ignoresMouseEvents = !inside
        if inside != state.expanded {
            // Collapse a little faster than expand so it feels responsive.
            let anim: Animation = inside ? .spring(response: 0.35, dampingFraction: 0.8) : .spring(response: 0.25, dampingFraction: 0.9)
            withAnimation(anim) {
                state.expanded = inside
                if inside && isDragging { state.select(.shelf) }   // dragging something in: show the shelf
            }
        }
    }
}
