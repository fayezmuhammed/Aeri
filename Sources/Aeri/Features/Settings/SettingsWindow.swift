import AppKit
import SwiftUI

/// The Settings window, opened from the gear menu. Created once and reused.
final class SettingsWindow {
    static var shared: SettingsWindow?

    private let state: NotchState
    private let weather: Weather
    private var window: NSWindow?

    init(state: NotchState, weather: Weather) {
        self.state = state
        self.weather = weather
    }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(state: state, weather: weather))
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
