import Combine
import CoreLocation
import Foundation

struct CachedWeather: Codable {
    let outdoorCelsius: Double
    let humidityPercent: Double
    let fetchedAt: Date
}

@MainActor
final class WeatherService: NSObject, ObservableObject {
    private let session: URLSession
    private let cacheURL: URL
    private let locationManager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    @Published private(set) var lastWeather: CachedWeather?
    @Published private(set) var isStale: Bool = false
    @Published private(set) var lastError: String?
    /// Human-readable line for the dashboard (e.g. coordinates when GPS is used).
    @Published private(set) var locationStatusLine: String = "Locating…"

    private(set) var lastCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    private(set) var hasValidCoordinate: Bool = false

    /// Use for carbon API when today’s GPS failed — last saved fix, then Illinois default (not a random coast).
    var coordinateForCarbon: CLLocationCoordinate2D {
        if hasValidCoordinate {
            return lastCoordinate
        }
        let lat = UserDefaults.standard.double(forKey: "last_known_lat")
        let lon = UserDefaults.standard.double(forKey: "last_known_lon")
        if abs(lat) > 0.01, abs(lon) > 0.01 {
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return CLLocationCoordinate2D(latitude: 41.9293, longitude: -88.7504)
    }

    private func persistLastKnownCoordinate(_ coordinate: CLLocationCoordinate2D) {
        UserDefaults.standard.set(coordinate.latitude, forKey: "last_known_lat")
        UserDefaults.standard.set(coordinate.longitude, forKey: "last_known_lon")
    }

    private let throttleInterval: TimeInterval = 15 * 60
    private var lastFetchAt: Date?

    override init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        session = URLSession(configuration: config)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("weather_cache.json")
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.distanceFilter = 50
        loadDiskCache()
    }

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        if let cached = try? JSONDecoder().decode(CachedWeather.self, from: data) {
            lastWeather = cached
            isStale = true
        }
    }

    private func saveDiskCache(_ weather: CachedWeather) throws {
        let data = try JSONEncoder().encode(weather)
        try data.write(to: cacheURL, options: .atomic)
    }

    func refreshWeatherIfNeeded() async {
        if let last = lastFetchAt, Date().timeIntervalSince(last) < throttleInterval, lastWeather != nil {
            return
        }
        await refreshWeather()
    }

    /// Always hits the network (use after manual Refresh).
    func refreshWeather() async {
        lastError = nil
        locationStatusLine = "Getting your location…"

        guard let coordinate = await requestCoordinate() else {
            if lastError == nil {
                lastError = "Location needed for live weather. Enable Location for EcoWeather in Settings."
            }
            locationStatusLine = "Location unavailable"
            isStale = lastWeather != nil
            return
        }

        lastCoordinate = coordinate
        hasValidCoordinate = true
        locationStatusLine = String(
            format: "GPS · %.4f°, %.4f°",
            coordinate.latitude,
            coordinate.longitude
        )

        if let key = openWeatherMapKey, !key.isEmpty {
            await fetchOpenWeatherMap(coordinate: coordinate, apiKey: key)
        } else {
            await fetchOpenMeteo(coordinate: coordinate)
        }
    }

    private var openWeatherMapKey: String? {
        let k = UserDefaults.standard.string(forKey: "openweathermap_api_key")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty == false) ? k : nil
    }

    private func fetchOpenWeatherMap(coordinate: CLLocationCoordinate2D, apiKey: String) async {
        var components = URLComponents(string: "https://api.openweathermap.org/data/2.5/weather")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(coordinate.longitude)),
            URLQueryItem(name: "appid", value: apiKey),
            URLQueryItem(name: "units", value: "imperial")
        ]

        guard let url = components.url else {
            lastError = "Invalid OpenWeatherMap URL"
            return
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                if let http = response as? HTTPURLResponse, http.statusCode == 401 {
                    lastError = "OpenWeatherMap API key rejected — check Debug menu."
                } else {
                    lastError = "OpenWeatherMap HTTP error"
                }
                isStale = lastWeather != nil
                return
            }
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let main = obj?["main"] as? [String: Any]
            let tempF = (main?["temp"] as? Double) ?? 0
            let humidity = (main?["humidity"] as? Double) ?? 50
            let celsius = (tempF - 32) * 5 / 9
            let decoded = CachedWeather(outdoorCelsius: celsius, humidityPercent: humidity, fetchedAt: Date())
            lastWeather = decoded
            lastFetchAt = Date()
            isStale = false
            try saveDiskCache(decoded)
            locationStatusLine = String(
                format: "OpenWeather · GPS %.4f°, %.4f°",
                coordinate.latitude,
                coordinate.longitude
            )
        } catch {
            lastError = error.localizedDescription
            isStale = lastWeather != nil
        }
    }

    private func fetchOpenMeteo(coordinate: CLLocationCoordinate2D) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else {
            lastError = "Invalid weather URL"
            return
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let decoded = try parseOpenMeteoCurrent(data: data)
            lastWeather = decoded
            lastFetchAt = Date()
            isStale = false
            try saveDiskCache(decoded)
            locationStatusLine = String(
                format: "Open-Meteo · GPS %.4f°, %.4f°",
                coordinate.latitude,
                coordinate.longitude
            )
        } catch {
            lastError = error.localizedDescription
            isStale = lastWeather != nil
        }
    }

    private func parseOpenMeteoCurrent(data: Data) throws -> CachedWeather {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let current = obj?["current"] as? [String: Any]
        let temp = doubleValue(current?["temperature_2m"]) ?? 0
        let humidity = doubleValue(current?["relative_humidity_2m"]) ?? 50
        return CachedWeather(outdoorCelsius: temp, humidityPercent: humidity, fetchedAt: Date())
    }

    private func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    private func requestCoordinate() async -> CLLocationCoordinate2D? {
        let status = locationManager.authorizationStatus

        if status == .denied || status == .restricted {
            lastError = "Location access denied — enable Location for EcoWeather in Settings to use weather at your position."
            return nil
        }

        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            for _ in 0 ..< 150 {
                try? await Task.sleep(nanoseconds: 200_000_000)
                let s = locationManager.authorizationStatus
                if s == .denied || s == .restricted {
                    lastError = "Location access denied — enable Location in Settings."
                    return nil
                }
                if s == .authorizedAlways || s == .authorizedWhenInUse {
                    break
                }
            }
        }

        guard locationManager.authorizationStatus == .authorizedAlways
            || locationManager.authorizationStatus == .authorizedWhenInUse
        else {
            lastError = "Location permission not granted."
            return nil
        }

        return await withCheckedContinuation { continuation in
            locationContinuation = continuation
            locationManager.startUpdatingLocation()

            Task {
                try? await Task.sleep(nanoseconds: 18_000_000_000)
                await MainActor.run {
                    if self.locationContinuation != nil {
                        self.locationManager.stopUpdatingLocation()
                        self.lastError = "GPS fix timed out — try again outdoors or check Settings ▸ Privacy ▸ Location Services."
                        self.locationContinuation?.resume(returning: nil)
                        self.locationContinuation = nil
                    }
                }
            }
        }
    }
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        let coord = loc.coordinate
        guard coord.latitude != 0, coord.longitude != 0 else { return }

        Task { @MainActor in
            manager.stopUpdatingLocation()
            lastCoordinate = coord
            hasValidCoordinate = true
            persistLastKnownCoordinate(coord)
            locationContinuation?.resume(returning: coord)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            manager.stopUpdatingLocation()
            lastError = "Location error: \(error.localizedDescription)"
            locationContinuation?.resume(returning: nil)
            locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                break
            case .denied, .restricted:
                break
            default:
                break
            }
        }
    }
}
