import ServiceManagement

/// Wraps SMAppService.mainApp, which only works from a real .app bundle (not `swift run`).
final class LaunchAtLogin: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status

    var isAvailable: Bool { Bundle.main.bundleURL.pathExtension == "app" }
    var isOn: Bool { status == .enabled || status == .requiresApproval }
    /// macOS sometimes wants the user to allow the login item in System Settings first.
    var needsApproval: Bool { status == .requiresApproval }

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Aeri: launch at login change failed: \(error)")
        }
        reload()
    }

    func reload() { status = SMAppService.mainApp.status }

    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}
