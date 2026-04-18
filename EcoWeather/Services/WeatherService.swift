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
    private var coordinateContinuation: CheckedContinuation<CLLocationCoordinate2D, Never>?

    @Published private(set) var lastWeather: CachedWeather?
    @Published private(set) var isStale: Bool = false
    @Published private(set) var lastError: String?
    private(set) var lastCoordinate: CLLocationCoordinate2D = WeatherService.fallbackCoordinate

    private let throttleInterval: TimeInterval = 15 * 60
    private var lastFetchAt: Date?

    override init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("weather_cache.json")
        super.init()
        locationManager.delegate = self
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

    func refreshWeather() async {
        lastError = nil
        let coordinate = await requestCoordinate()
        await fetchOpenMeteo(coordinate: coordinate)
    }

    private func fetchOpenMeteo(coordinate: CLLocationCoordinate2D) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current_weather", value: "true"),
            URLQueryItem(name: "hourly", value: "relativehumidity_2m"),
            URLQueryItem(name: "forecast_days", value: "1")
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
            let decoded = try parseOpenMeteo(data: data)
            lastWeather = decoded
            lastFetchAt = Date()
            isStale = false
            try saveDiskCache(decoded)
        } catch {
            lastError = error.localizedDescription
            isStale = lastWeather != nil
        }
    }

    private func parseOpenMeteo(data: Data) throws -> CachedWeather {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let current = obj?["current_weather"] as? [String: Any]
        let temp = (current?["temperature"] as? Double) ?? 0

        var humidity = 50.0
        if let hourly = obj?["hourly"] as? [String: Any],
           let rh = hourly["relativehumidity_2m"] as? [Double],
           let first = rh.first {
            humidity = first
        }

        return CachedWeather(outdoorCelsius: temp, humidityPercent: humidity, fetchedAt: Date())
    }

    private func requestCoordinate() async -> CLLocationCoordinate2D {
        await withCheckedContinuation { continuation in
            coordinateContinuation = continuation
            let status = locationManager.authorizationStatus
            switch status {
            case .notDetermined:
                locationManager.requestWhenInUseAuthorization()
            case .authorizedAlways, .authorizedWhenInUse:
                locationManager.requestLocation()
            case .denied, .restricted:
                continuation.resume(returning: WeatherService.fallbackCoordinate)
            @unknown default:
                continuation.resume(returning: WeatherService.fallbackCoordinate)
            }
        }
    }

    fileprivate static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)
}

extension WeatherService: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let coord = locations.last?.coordinate ?? WeatherService.fallbackCoordinate
        Task { @MainActor in
            lastCoordinate = coord
            coordinateContinuation?.resume(returning: coord)
            coordinateContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            coordinateContinuation?.resume(returning: WeatherService.fallbackCoordinate)
            coordinateContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                coordinateContinuation?.resume(returning: WeatherService.fallbackCoordinate)
                coordinateContinuation = nil
            case .notDetermined:
                break
            @unknown default:
                coordinateContinuation?.resume(returning: WeatherService.fallbackCoordinate)
                coordinateContinuation = nil
            }
        }
    }
}
