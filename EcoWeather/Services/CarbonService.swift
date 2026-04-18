import Combine
import CoreLocation
import Foundation

struct CachedCarbon: Codable {
    let co2GramsPerKWh: Double
    let fetchedAt: Date
}

@MainActor
final class CarbonService: ObservableObject {
    private let session: URLSession
    private let cacheURL: URL

    @Published private(set) var lastCarbon: CachedCarbon?
    @Published private(set) var usedFallback: Bool = false
    @Published private(set) var lastError: String?

    private let staleInterval: TimeInterval = 6 * 60 * 60

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        session = URLSession(configuration: config)
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        cacheURL = dir.appendingPathComponent("carbon_cache.json")
        loadDiskCache()
    }

    private func loadDiskCache() {
        guard let data = try? Data(contentsOf: cacheURL) else { return }
        if let cached = try? JSONDecoder().decode(CachedCarbon.self, from: data) {
            lastCarbon = cached
        }
    }

    private func saveDiskCache(_ value: CachedCarbon) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: cacheURL, options: .atomic)
    }

    func token() -> String {
        UserDefaults.standard.string(forKey: "electricitymaps_token") ?? ""
    }

    func refreshCarbon(coordinate: CLLocationCoordinate2D, isoRegion: String) async -> Double {
        lastError = nil
        usedFallback = false

        let token = token()
        if !token.isEmpty, let live = await fetchLiveCarbon(token: token, coordinate: coordinate) {
            let cached = CachedCarbon(co2GramsPerKWh: live, fetchedAt: Date())
            lastCarbon = cached
            try? saveDiskCache(cached)
            return live
        }

        if let last = lastCarbon, Date().timeIntervalSince(last.fetchedAt) < staleInterval {
            usedFallback = true
            lastError = lastError ?? "Using cached carbon data"
            return last.co2GramsPerKWh
        }

        let estimate = regionalFallback(isoRegion: isoRegion)
        usedFallback = true
        lastError = lastError ?? "Using regional estimate"
        let cached = CachedCarbon(co2GramsPerKWh: estimate, fetchedAt: Date())
        lastCarbon = cached
        try? saveDiskCache(cached)
        return estimate
    }

    private func fetchLiveCarbon(token: String, coordinate: CLLocationCoordinate2D) async -> Double? {
        var components = URLComponents(string: "https://api.electricitymap.org/v3/carbon-intensity/latest")!
        components.queryItems = [
            URLQueryItem(name: "lat", value: String(coordinate.latitude)),
            URLQueryItem(name: "lon", value: String(coordinate.longitude))
        ]

        guard let url = components.url else { return nil }

        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "auth-token")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                lastError = "Carbon API HTTP error"
                return nil
            }
            return parseCarbonJSON(data)
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    private func parseCarbonJSON(_ data: Data) -> Double? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let v = obj["carbonIntensity"] as? Double {
                return v
            }
            if let v = obj["carbonIntensity"] as? Int {
                return Double(v)
            }
            if let dataObj = obj["data"] as? [String: Any],
               let ci = dataObj["carbonIntensity"] as? Double {
                return ci
            }
        }
        lastError = "Unexpected carbon JSON"
        return nil
    }

    private func regionalFallback(isoRegion: String) -> Double {
        let key = isoRegion.uppercased()
        let table: [String: Double] = [
            "US": 380,
            "DE": 380,
            "GB": 220,
            "FR": 60,
            "CA": 120,
            "AU": 500,
            "JP": 450,
            "IN": 700,
            "CN": 550,
            "BR": 120,
            "MX": 380,
            "ES": 180,
            "IT": 320,
            "NL": 400,
            "SE": 30,
            "NO": 20
        ]
        return table[key] ?? 300
    }
}
