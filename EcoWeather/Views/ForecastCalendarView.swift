import SwiftUI

/// Two-week strip from daily forecast (same source as the 10-day strip).
struct ForecastCalendarView: View {
    let days: [DailyForecastDay]
    let useFahrenheit: Bool

    private var calendarDays: [DailyForecastDay] {
        Array(days.prefix(14))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("2-week outlook")
                .font(.headline)
            Text("Tap a day for the same codes as the horizontal forecast.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if calendarDays.isEmpty {
                Text("Calendar fills when the forecast loads.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7),
                    spacing: 10
                ) {
                    ForEach(calendarDays) { day in
                        calendarCell(day)
                    }
                }
            }
        }
        .padding()
        .liquidGlassCard()
    }

    private func calendarCell(_ day: DailyForecastDay) -> some View {
        VStack(spacing: 6) {
            Text(day.weekdayShort.uppercased())
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.tertiary)
            Text(day.dayNumber)
                .font(.caption.weight(.semibold))
            Image(systemName: DailyForecastDay.wmoSymbolName(code: day.weatherCode))
                .font(.caption)
                .symbolRenderingMode(.hierarchical)
                .frame(height: 14)
            Text(day.highLowFormatted(useFahrenheit: useFahrenheit))
                .font(.system(size: 9, weight: .medium, design: .rounded))
                .minimumScaleFactor(0.8)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.08))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5)
        }
    }
}
