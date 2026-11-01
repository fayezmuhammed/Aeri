import SwiftUI

struct WeatherView: View {
    @ObservedObject var weather: Weather
    @StateObject private var input = CityInput()

    var body: some View {
        if weather.place == nil || input.editing {
            cityField
        } else {
            HStack(spacing: 14) {
                Image(systemName: weather.symbol)
                    .symbolRenderingMode(.multicolor)
                    .font(.system(size: 30))
                VStack(alignment: .leading, spacing: 2) {
                    Text(weather.temperature.map(Self.degrees) ?? "–")
                        .font(.system(size: 24, weight: .semibold).monospacedDigit())
                    Text(weather.summary).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Button { input.text = ""; input.editing = true } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "location.fill").font(.system(size: 9))
                            Text(weather.place?.name ?? "").font(.system(size: 12, weight: .semibold))
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .help("Change city")
                    if let h = weather.high, let l = weather.low {
                        Text("H \(Self.degrees(h))  L \(Self.degrees(l))")
                            .font(.system(size: 11).monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                    }
                    if let e = weather.error {
                        Text(e).font(.system(size: 10)).foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private var cityField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.white.opacity(0.6))
            TextField("Enter your city", text: $input.text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onSubmit {
                    weather.setCity(input.text)
                    input.editing = false
                }
            if weather.loading { ProgressView().controlSize(.small) }
            if let e = weather.error { Text(e).font(.system(size: 10)).foregroundStyle(.orange) }
            if weather.place != nil {
                Button("Cancel") { input.editing = false }.buttonStyle(PressableButtonStyle()).font(.system(size: 11))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(0.1)))
    }

    static func degrees(_ t: Double) -> String { "\(Int(t.rounded()))°" }
}

/// Stands in for @State, which needs macros.
final class CityInput: ObservableObject {
    @Published var text = ""
    @Published var editing = false
}
