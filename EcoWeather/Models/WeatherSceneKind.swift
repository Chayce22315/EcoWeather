import Foundation

/// Visual weather scenes for sky backgrounds and preview tabs (WMO-inspired).
enum WeatherSceneKind: String, CaseIterable, Identifiable {
    case live
    case sunny
    case partlyCloudy
    case cloudy
    case rain
    case thunderstorm
    case isolatedThunder
    case nightClear
    case nightPartlyCloudy
    case nightCloudy
    case nightRain
    case nightThunderstorm
    case nightIsolatedThunder

    var id: String { rawValue }

    var shortTitle: String {
        switch self {
        case .live: return "Live"
        case .sunny: return "Sunny"
        case .partlyCloudy: return "Partly cloudy"
        case .cloudy: return "Cloudy"
        case .rain: return "Rain"
        case .thunderstorm: return "Thunder"
        case .isolatedThunder: return "Dry lightning"
        case .nightClear: return "Clear night"
        case .nightPartlyCloudy: return "Night · partly"
        case .nightCloudy: return "Night · cloudy"
        case .nightRain: return "Night · rain"
        case .nightThunderstorm: return "Night · thunder"
        case .nightIsolatedThunder: return "Night · dry bolt"
        }
    }

    var isNight: Bool {
        switch self {
        case .nightClear, .nightPartlyCloudy, .nightCloudy, .nightRain, .nightThunderstorm, .nightIsolatedThunder:
            return true
        default:
            return false
        }
    }

    var showsRain: Bool {
        switch self {
        case .rain, .thunderstorm, .nightRain, .nightThunderstorm:
            return true
        default:
            return false
        }
    }

    var showsThunder: Bool {
        switch self {
        case .thunderstorm, .isolatedThunder, .nightThunderstorm, .nightIsolatedThunder:
            return true
        default:
            return false
        }
    }

    /// Light droplets on glass (no full rain layer).
    var showsMistOnGlass: Bool {
        switch self {
        case .partlyCloudy, .nightPartlyCloudy, .cloudy, .nightCloudy:
            return true
        default:
            return false
        }
    }

    /// Derive a scene from Open-Meteo-style fields (WMO code, is_day, optional precip mm).
    static func fromLive(wmoCode: Int, isDay: Bool, precipitationMm: Double) -> WeatherSceneKind {
        let night = !isDay
        let precip = precipitationMm
        let thunderCodes = 95 ... 99
        if thunderCodes.contains(wmoCode) {
            if precip < 0.05 {
                return night ? .nightIsolatedThunder : .isolatedThunder
            }
            return night ? .nightThunderstorm : .thunderstorm
        }

        let isRainCode = (51 ... 67).contains(wmoCode) || (80 ... 82).contains(wmoCode)
        if isRainCode || (71 ... 77).contains(wmoCode) || [85, 86].contains(wmoCode) {
            return night ? .nightRain : .rain
        }

        switch wmoCode {
        case 0, 1:
            return night ? .nightClear : .sunny
        case 2:
            return night ? .nightPartlyCloudy : .partlyCloudy
        case 3, 45, 48:
            return night ? .nightCloudy : .cloudy
        default:
            return night ? .nightPartlyCloudy : .partlyCloudy
        }
    }
}
