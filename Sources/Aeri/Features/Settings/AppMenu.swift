import AppKit

/// Gear menu in the notch: version, Settings…, Quit.
/// Shown as an NSMenu because popUp blocks until it closes, which lets the notch stay open
/// (`NotchState.holdOpen`) while the cursor is over the menu, outside the notch shape.
enum AppMenu {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static func show(state: NotchState) {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Aeri \(version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        menu.addItem(ActionItem(title: "Settings…", key: ",") { SettingsWindow.shared?.show() })
        menu.addItem(.separator())
        menu.addItem(ActionItem(title: "Quit Aeri", key: "q") { NSApp.terminate(nil) })

        state.holdOpen = true
        menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
        state.holdOpen = false
    }
}

/// NSMenuItem that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, key: String = "", handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
