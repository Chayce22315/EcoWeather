import Combine
import CoreLocation
import Foundation

struct CachedWeather: Codable {
    let outdoorCelsius: Double
    let humidityPercent: Double
    let fetchedAt: Date
    /// WMO weather code when sourced from Open-Meteo (or mapped from OpenWeatherMap).
    var wmoWeatherCode: Int?
    /// Open-Meteo `is_day` (1 day / 0 night). Nil when unknown.
    var isDay: Bool?
    /// Recent precipitation in millimeters when available (Open-Meteo `precipitation`).
    var precipitationMm: Double?
}

@MainActor
final class WeatherService: NSObject, ObservableObject {
    private let session: URLSession
    private let cacheURL: URL
    private let locationManager = CLLocationManager()
    private let geocoder = CLGeocoder()
    private var locationContinuation: CheckedContinuation<CLLocationCoordinate2D?, Never>?

    @Published private(set) var lastWeather: CachedWeather?
    @Published private(set) var isStale: Bool = false
    @Published private(set) var lastError: String?
    /// Reverse-geocoded place name, e.g. "DeKalb, IL"
    @Published private(set) var cityDisplayName: String = ""
    /// Human-readable coordinates under the city (e.g. 41.93° N, 88.75° W)
    @Published private(set) var locationDetailLine: String = ""
    /// 10-day daily forecast (Open-Meteo WMO codes)
    @Published private(set) var dailyForecast: [DailyForecastDay] = []

    private(set) var lastCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 0, longitude: 0)
    private(set) var hasValidCoordinate: Bool = false

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

    func refreshWeather() async {
        lastError = nil
        dailyForecast = []
        cityDisplayName = "Locating…"
        locationDetailLine = ""

        guard let coordinate = await requestCoordinate() else {
            if lastError == nil {
                lastError = "Location needed for live weather. Enable Location for EcoWeather in Settings."
            }
            cityDisplayName = "Location off"
            isStale = lastWeather != nil
            return
        }

        lastCoordinate = coordinate
        hasValidCoordinate = true
        persistLastKnownCoordinate(coordinate)
        locationDetailLine = Self.formatCoordinates(coordinate)

        await updateCityName(for: coordinate)

        if let key = openWeatherMapKey, !key.isEmpty {
            await fetchOpenWeatherMap(coordinate: coordinate, apiKey: key)
            await fetchOpenMeteoDailyOnly(coordinate: coordinate)
        } else {
            await fetchOpenMeteoCurrentAndDaily(coordinate: coordinate)
        }
    }

    private var openWeatherMapKey: String? {
        let k = UserDefaults.standard.string(forKey: "openweathermap_api_key")?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (k?.isEmpty == false) ? k : nil
    }

    private func updateCityName(for coordinate: CLLocationCoordinate2D) async {
        let loc = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(loc)
            if let p = placemarks.first {
                if let locality = p.locality {
                    if let admin = p.administrativeArea {
                        cityDisplayName = "\(locality), \(admin)"
                    } else {
                        cityDisplayName = locality
                    }
                } else if let name = p.name {
                    cityDisplayName = name
                } else {
                    cityDisplayName = "Current location"
                }
            } else {
                cityDisplayName = "Current location"
            }
        } catch {
            cityDisplayName = "Weather location"
        }
    }

    private static func formatCoordinates(_ c: CLLocationCoordinate2D) -> String {
        let latH = c.latitude >= 0 ? "N" : "S"
        let lonH = c.longitude >= 0 ? "E" : "W"
        return String(
            format: "%.2f° %@ · %.2f° %@",
            abs(c.latitude),
            latH,
            abs(c.longitude),
            lonH
        )
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
            let decoded = parseOpenWeatherMapCurrent(obj: obj, celsius: celsius, humidity: humidity)
            lastWeather = decoded
            lastFetchAt = Date()
            isStale = false
            try saveDiskCache(decoded)
        } catch {
            lastError = error.localizedDescription
            isStale = lastWeather != nil
        }
    }

    private func fetchOpenMeteoCurrentAndDaily(coordinate: CLLocationCoordinate2D) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,weather_code,is_day,precipitation"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "10"),
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
            let (current, daily) = try parseOpenMeteoCombined(data: data)
            lastWeather = current
            dailyForecast = daily
            lastFetchAt = Date()
            isStale = false
            try saveDiskCache(current)
        } catch {
            lastError = error.localizedDescription
            isStale = lastWeather != nil
        }
    }

    private func fetchOpenMeteoDailyOnly(coordinate: CLLocationCoordinate2D) async {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(coordinate.latitude)),
            URLQueryItem(name: "longitude", value: String(coordinate.longitude)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "10"),
            URLQueryItem(name: "timezone", value: "auto")
        ]

        guard let url = components.url else { return }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else { return }
            let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            dailyForecast = parseDailyForecast(from: obj) ?? []
        } catch {
            #if DEBUG
            print("Daily forecast fetch: \(error.localizedDescription)")
            #endif
        }
    }

    private func parseOpenMeteoCombined(data: Data) throws -> (CachedWeather, [DailyForecastDay]) {
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let current = obj?["current"] as? [String: Any]
        let temp = doubleValue(current?["temperature_2m"]) ?? 0
        let humidity = doubleValue(current?["relative_humidity_2m"]) ?? 50
        let wmo = intValue(current?["weather_code"])
        let isDayInt = intValue(current?["is_day"])
        let isDay: Bool? = isDayInt.map { $0 != 0 }
        let precip = doubleValue(current?["precipitation"]) ?? 0
        let weather = CachedWeather(
            outdoorCelsius: temp,
            humidityPercent: humidity,
            fetchedAt: Date(),
            wmoWeatherCode: wmo,
            isDay: isDay,
            precipitationMm: precip
        )
        let daily = parseDailyForecast(from: obj) ?? []
        return (weather, daily)
    }

    private func parseDailyForecast(from obj: [String: Any]?) -> [DailyForecastDay]? {
        guard let obj,
              let daily = obj["daily"] as? [String: Any],
              let timeStrings = daily["time"] as? [String]
        else { return nil }

        let codes = intArray(from: daily["weather_code"]) ?? []
        let maxT = doubleArray(from: daily["temperature_2m_max"]) ?? []
        let minT = doubleArray(from: daily["temperature_2m_min"]) ?? []
        let precip = intArray(from: daily["precipitation_probability_max"]) ?? []

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]

        var result: [DailyForecastDay] = []
        for i in 0 ..< min(timeStrings.count, 10) {
            guard let date = formatter.date(from: timeStrings[i]) else { continue }
            let code = i < codes.count ? codes[i] : 2
            let hi = i < maxT.count ? maxT[i] : 0
            let lo = i < minT.count ? minT[i] : 0
            let pr = i < precip.count ? precip[i] : 0
            result.append(
                DailyForecastDay(
                    id: timeStrings[i],
                    date: date,
                    tempMaxC: hi,
                    tempMinC: lo,
                    precipProb: pr,
                    weatherCode: code
                )
            )
        }
        return result
    }

    private func intArray(from any: Any?) -> [Int]? {
        if let a = any as? [Int] { return a }
        if let a = any as? [Double] { return a.map { Int($0.rounded()) } }
        return nil
    }

    private func doubleArray(from any: Any?) -> [Double]? {
        if let a = any as? [Double] { return a }
        if let a = any as? [Int] { return a.map { Double($0) } }
        return nil
    }

    private func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let d as Double: return d
        case let i as Int: return Double(i)
        case let n as NSNumber: return n.doubleValue
        default: return nil
        }
    }

    private func intValue(_ any: Any?) -> Int? {
        switch any {
        case let i as Int: return i
        case let d as Double: return Int(d.rounded())
        case let n as NSNumber: return n.intValue
        default: return nil
        }
    }

    /// Map OpenWeatherMap `weather[].id` to a WMO-style code for shared scene logic.
    private func wmoStyleCodeFromOpenWeatherId(_ id: Int) -> Int {
        switch id {
        case 200 ..< 300: return 95
        case 300 ..< 400: return 55
        case 500 ..< 600: return 65
        case 600 ..< 700: return 75
        case 700 ..< 800: return 45
        case 800: return 0
        case 801: return 1
        case 802: return 2
        case 803, 804: return 3
        default: return 2
        }
    }

    private func parseOpenWeatherMapCurrent(obj: [String: Any]?, celsius: Double, humidity: Double) -> CachedWeather {
        let weatherArr = obj?["weather"] as? [[String: Any]]
        let firstId = weatherArr?.compactMap { intValue($0["id"]) }.first
        let wmo = firstId.map { wmoStyleCodeFromOpenWeatherId($0) }

        var isDay: Bool?
        if let sys = obj?["sys"] as? [String: Any],
           let dt = intValue(obj?["dt"]),
           let sunrise = intValue(sys["sunrise"]),
           let sunset = intValue(sys["sunset"]) {
            isDay = dt >= sunrise && dt < sunset
        }

        return CachedWeather(
            outdoorCelsius: celsius,
            humidityPercent: humidity,
            fetchedAt: Date(),
            wmoWeatherCode: wmo,
            isDay: isDay,
            precipitationMm: nil
        )
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
            _ = manager.authorizationStatus
        }
    }
}
