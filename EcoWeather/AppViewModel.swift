import CoreLocation
import Foundation
import SwiftUI

@MainActor
final class AppViewModel: ObservableObject {
    @Published var indoorCelsius: Double = 22.0
    @Published var decision: EcoDecisionModel?
    @Published var isLoading = false
    @Published var bannerMessage: String?

    @Published var lastOutdoor: Double = 0
    @Published var lastHumidity: Double = 50
    @Published var lastCo2: Double = 0
    @Published var weatherStale: Bool = false

    let weather = WeatherService()
    let carbon = CarbonService()
    let engine = EcoEngine()

    private var lastCoordinate: CLLocationCoordinate2D = CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060)

    func refresh() async {
        isLoading = true
        bannerMessage = nil
        defer { isLoading = false }

        await weather.refreshWeather()
        if let w = weather.lastWeather {
            lastOutdoor = w.outdoorCelsius
            lastHumidity = w.humidityPercent
        }
        lastCoordinate = weather.coordinateForCarbon

        let region = Locale.current.region?.identifier ?? "US"
        let co2 = await carbon.refreshCarbon(coordinate: lastCoordinate, isoRegion: region)
        lastCo2 = co2

        let outdoor = Float(lastOutdoor)
        let indoor = Float(indoorCelsius)
        let humidity = Float(lastHumidity)

        let previousDecision = decision
        decision = engine.computeDecision(
            withOutdoorTemp: outdoor,
            indoorTemp: indoor,
            humidity: humidity,
            co2Intensity: Float(co2)
        )

        EcoNotificationService.shared.evaluateDecisionChange(previous: previousDecision, current: decision)

        weatherStale = weather.isStale
        if weather.isStale {
            bannerMessage = "Weather data may be stale or from cache."
        }
        if let err = weather.lastError, !err.isEmpty {
            bannerMessage = [bannerMessage, err].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        }
        if carbon.usedFallback {
            bannerMessage = (bannerMessage ?? "") + (bannerMessage == nil ? "" : " ") + "Carbon data used fallback or cache."
        }
    }

    func carbonTintColor() -> Color {
        let level = decision?.recommendationLevel ?? 1
        switch level {
        case 0:
            return Color(red: 0, green: 0.659, blue: 0.420)
        case 2:
            return Color(red: 1, green: 0.298, blue: 0.298)
        default:
            return Color(red: 1, green: 0.749, blue: 0)
        }
    }
}
