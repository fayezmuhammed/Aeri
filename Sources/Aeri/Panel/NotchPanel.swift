import AppKit

/// Borderless panel over the notch, above the menu bar.
final class NotchPanel: NSPanel {
    init(rect: NSRect) {
        super.init(contentRect: rect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar + 1            // above the menu bar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        isMovable = false
        ignoresMouseEvents = true
    }
    override var canBecomeKey: Bool { true }
}
