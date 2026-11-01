import AppKit
import ServiceManagement

/// Gear menu in the notch: version, launch at login, quit.
/// Shown as an NSMenu because popUp blocks until it closes, which lets the notch stay open
/// (`NotchState.holdOpen`) while the cursor is over the menu, outside the notch shape.
enum AppMenu {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// SMAppService only works from a real .app bundle, not `swift run`.
    static var canLaunchAtLogin: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    static func show(state: NotchState) {
        let menu = NSMenu()
        let title = NSMenuItem(title: "Aeri \(version)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())

        let login = ActionItem(title: "Launch at Login") {
            let service = SMAppService.mainApp
            do {
                if service.status == .enabled { try service.unregister() } else { try service.register() }
            } catch {
                NSSound.beep()
            }
        }
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        login.isEnabled = canLaunchAtLogin
        if !canLaunchAtLogin { login.toolTip = "Available in the packaged Aeri.app" }
        menu.addItem(login)

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
