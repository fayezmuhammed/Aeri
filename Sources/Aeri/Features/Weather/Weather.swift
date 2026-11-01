import Foundation

/// Current conditions and today's range from Open-Meteo (free, no API key or account).
/// The city is entered once, geocoded by Open-Meteo, and saved in UserDefaults.
final class Weather: ObservableObject {
    struct Place: Codable { var name: String; var latitude: Double; var longitude: Double }

    @Published private(set) var place: Place?
    @Published private(set) var temperature: Double?
    @Published private(set) var high: Double?
    @Published private(set) var low: Double?
    @Published private(set) var code: Int?
    @Published private(set) var error: String?
    @Published private(set) var loading = false

    let unit = Locale.current.measurementSystem == .us ? "fahrenheit" : "celsius"
    private var fetchedAt: Date?
    private var timer: Timer?
    private static let placeKey = "weather.place"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.placeKey) {
            place = try? JSONDecoder().decode(Place.self, from: data)
        }
        refresh()
        timer = .scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.refresh() }
    }

    /// Refetch if data is older than 15 minutes (called when the notch opens).
    func refreshIfStale() {
        if fetchedAt.map({ Date().timeIntervalSince($0) > 15 * 60 }) ?? true { refresh() }
    }

    func setCity(_ name: String) {
        let q = name.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return }
        var c = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        c.queryItems = [.init(name: "name", value: q), .init(name: "count", value: "1")]
        loading = true
        error = nil
        get(c.url!) { [weak self] (r: GeoResponse) in
            guard let self else { return }
            guard let hit = r.results?.first else {
                self.loading = false
                self.error = "City not found"
                return
            }
            let p = Place(name: hit.name, latitude: hit.latitude, longitude: hit.longitude)
            self.place = p
            UserDefaults.standard.set(try? JSONEncoder().encode(p), forKey: Self.placeKey)
            self.refresh()
        }
    }

    func clearCity() {
        place = nil
        temperature = nil
        UserDefaults.standard.removeObject(forKey: Self.placeKey)
    }

    func refresh() {
        guard let p = place else { return }
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        c.queryItems = [
            .init(name: "latitude", value: String(p.latitude)),
            .init(name: "longitude", value: String(p.longitude)),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "forecast_days", value: "1"),
            .init(name: "timezone", value: "auto"),
            .init(name: "temperature_unit", value: unit),
        ]
        loading = true
        get(c.url!) { [weak self] (r: ForecastResponse) in
            guard let self else { return }
            self.loading = false
            self.error = nil
            self.fetchedAt = Date()
            self.temperature = r.current.temperature_2m
            self.code = r.current.weather_code
            self.high = r.daily.temperature_2m_max.first
            self.low = r.daily.temperature_2m_min.first
        }
    }

    private func get<T: Decodable>(_ url: URL, _ done: @escaping (T) -> Void) {
        URLSession.shared.dataTask(with: url) { [weak self] data, _, err in
            let decoded = data.flatMap { try? JSONDecoder().decode(T.self, from: $0) }
            DispatchQueue.main.async {
                if let decoded { return done(decoded) }
                self?.loading = false
                self?.error = err == nil ? "Unexpected response" : "Offline"
            }
        }.resume()
    }

    // WMO weather codes, as used by Open-Meteo.
    var symbol: String {
        switch code ?? -1 {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51...57: return "cloud.drizzle.fill"
        case 61...67, 80...82: return "cloud.rain.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "thermometer.medium"
        }
    }

    var summary: String {
        switch code ?? -1 {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67: return "Rain"
        case 71...77: return "Snow"
        case 80...82: return "Showers"
        case 85, 86: return "Snow showers"
        case 95...99: return "Thunderstorm"
        default: return ""
        }
    }

    private struct GeoResponse: Decodable {
        struct Hit: Decodable { let name: String; let latitude: Double; let longitude: Double }
        let results: [Hit]?
    }

    private struct ForecastResponse: Decodable {
        struct Current: Decodable { let temperature_2m: Double; let weather_code: Int }
        struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
        let current: Current
        let daily: Daily
    }
}
