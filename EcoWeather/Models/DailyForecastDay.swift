import Foundation

struct DailyForecastDay: Identifiable, Equatable {
    let id: String
    let date: Date
    let tempMaxC: Double
    let tempMinC: Double
    let precipProb: Int
    let weatherCode: Int

    static func wmoHeadline(code: Int) -> String {
        switch code {
        case 0: return "Clear skies"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog possible"
        case 51 ... 57: return "Drizzle at times"
        case 61 ... 67: return "Rain likely"
        case 71 ... 77: return "Snow possible"
        case 80 ... 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorms"
        case 96 ... 99: return "Severe storms"
        default: return "Mixed conditions"
        }
    }

    static func wmoSymbolName(code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1: return "sun.max.circle.fill"
        case 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51 ... 57: return "cloud.drizzle.fill"
        case 61 ... 67: return "cloud.rain.fill"
        case 71 ... 77: return "cloud.snow.fill"
        case 80 ... 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.snow.fill"
        case 95 ... 99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }

    var predictionLine: String {
        let base = Self.wmoHeadline(code: weatherCode)
        if precipProb >= 40 {
            return "\(base) · up to \(precipProb)% rain/snow chance"
        }
        if precipProb >= 15 {
            return "\(base) · \(precipProb)% precip chance"
        }
        return base
    }

    func highLowFormatted(useFahrenheit: Bool) -> String {
        if useFahrenheit {
            let hi = tempMaxC * 9 / 5 + 32
            let lo = tempMinC * 9 / 5 + 32
            return String(format: "%.0f° / %.0f°", hi, lo)
        }
        return String(format: "%.0f° / %.0f°", tempMaxC, tempMinC)
    }

    var weekdayShort: String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }

    var dayNumber: String {
        date.formatted(.dateTime.day())
    }
}
