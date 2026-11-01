import AppKit
import SwiftUI

/// The Settings window, opened from the gear menu. Created once and reused.
final class SettingsWindow {
    static var shared: SettingsWindow?

    private let state: NotchState
    private let weather: Weather
    private let liveSettings: LiveSettings
    private let mediaKeys: MediaKeys
    private var window: NSWindow?

    init(state: NotchState, weather: Weather, liveSettings: LiveSettings, mediaKeys: MediaKeys) {
        self.state = state
        self.weather = weather
        self.liveSettings = liveSettings
        self.mediaKeys = mediaKeys
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(state: state, weather: weather, live: liveSettings, mediaKeys: mediaKeys))
            let w = NSWindow(contentViewController: host)
            w.title = "Aeri Settings"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        // Aeri is an accessory app, so it must activate to bring the window forward.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var state: NotchState
    @ObservedObject var weather: Weather
    @ObservedObject var live: LiveSettings
    @ObservedObject var mediaKeys: MediaKeys
    @StateObject private var login = LaunchAtLogin()
    @StateObject private var city = CityInput()

    var body: some View {
        Form {
            Section("General") {
                Toggle("Launch at Login", isOn: Binding(get: { login.isOn }, set: login.set))
                    .disabled(!login.isAvailable)
                if !login.isAvailable {
                    Text("Available when running the packaged Aeri.app.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if login.needsApproval {
                    HStack {
                        Text("Allow Aeri in Login Items to finish.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Login Items", action: login.openSystemSettings).controlSize(.small)
                    }
                }
            }

            Section {
                ForEach(NotchTab.allCases, id: \.self) { tab in
                    Toggle(isOn: Binding(get: { state.isEnabled(tab) }, set: { state.setEnabled(tab, $0) })) {
                        Label(tab.title, systemImage: tab.icon)
                    }
                    // The last remaining tab can't be turned off.
                    .disabled(state.isEnabled(tab) && state.enabledTabs.count == 1)
                }
            } header: {
                Text("Tabs")
            } footer: {
                Text("Choose which tabs appear in the notch. At least one stays on.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Toggle("Music indicator", isOn: $live.musicIndicator)
                Toggle("Battery and charging alerts", isOn: $live.batteryAlerts)
                Toggle("Volume and brightness bar", isOn: $live.levelBars)
                Toggle("Hide the system volume and brightness box", isOn: $live.replaceSystemHUD)
                    .disabled(!live.levelBars)
                if live.replaceSystemHUD && live.levelBars && !mediaKeys.trusted {
                    HStack {
                        Text("Needs Accessibility permission to intercept the keys.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Settings", action: mediaKeys.openAccessibilitySettings).controlSize(.small)
                    }
                }
                if !mediaKeys.trusted {
                    HStack {
                        Text("Allow Accessibility so live activities move aside instead of covering menus and status icons.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Allow", action: mediaKeys.requestAccess).controlSize(.small)
                    }
                }
            } header: {
                Text("Live Activities")
            } footer: {
                Text("Shown beside the notch while it's closed. Hidden when there's no free space in the menu bar.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Weather") {
                LabeledContent("City", value: weather.place?.name ?? "Not set")
                HStack {
                    TextField("Change city", text: $city.text, prompt: Text("Search for a city"))
                        .labelsHidden()
                        .onSubmit(searchCity)
                    if weather.loading { ProgressView().controlSize(.small) }
                    Button("Set", action: searchCity).disabled(city.text.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let error = weather.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
                Picker("Units", selection: $weather.units) {
                    ForEach(Weather.Units.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear(perform: login.reload)
    }

    private func searchCity() {
        weather.setCity(city.text)
        city.text = ""
    }
}
