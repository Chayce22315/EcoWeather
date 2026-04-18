import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @ObservedObject private var notifications = EcoNotificationService.shared
    @AppStorage("eco_notifications_enabled") private var notificationsEnabled = true
    @State private var showDetail = false
    @State private var showDebug = false

    private var useUS: Bool { Locale.current.measurementSystem == .us }

    var body: some View {
        ZStack {
            backgroundLayer
            ScrollView {
                VStack(spacing: 20) {
                    heroHeader
                    tenDaySection
                    notificationSection
                    DecisionOrbView()
                        .onTapGesture {
                            showDetail = true
                        }
                    recommendation
                    statusRow
                    if let banner = appModel.bannerMessage {
                        Text(banner)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    Button(action: {
                        Task { await appModel.refresh() }
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(appModel.isLoading)
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            cornerDebugTriggers
        }
        .task {
            await EcoNotificationService.shared.refreshAuthorizationStatus()
            await appModel.refresh()
        }
        .sheet(isPresented: $showDetail) {
            DetailPanelView()
                .environmentObject(appModel)
        }
        .sheet(isPresented: $showDebug) {
            DebugMenuView()
                .environmentObject(appModel)
        }
    }

    private var backgroundLayer: some View {
        ZStack {
            LinearGradient(
                colors: [
                    appModel.carbonTintColor().opacity(0.35),
                    Color.black.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
        .animation(.easeInOut(duration: 0.6), value: appModel.decision?.recommendationLevel ?? -1)
    }

    private var heroHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(cityHeadline)
                .font(.largeTitle.bold())
                .minimumScaleFactor(0.7)

            if !appModel.weather.locationDetailLine.isEmpty {
                Text(appModel.weather.locationDetailLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let w = appModel.weather.lastWeather {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(formattedOutdoor(fromCelsius: w.outdoorCelsius))
                        .font(.system(size: 56, weight: .thin, design: .rounded))
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("now")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        if appModel.weatherStale {
                            Text("Cached data")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.yellow.opacity(0.35))
                                .clipShape(Capsule())
                        }
                    }
                }
                Text(String(format: "Humidity %.0f%%", w.humidityPercent))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Text("Waiting for GPS + weather…")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }

            Text("EcoWeather")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.quaternary)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var cityHeadline: String {
        let c = appModel.weather.cityDisplayName
        if c.isEmpty || c == "Locating…" {
            return "Locating…"
        }
        return c
    }

    private var tenDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Next 10 days — live forecast")
                .font(.headline)
            Text("Open-Meteo daily outlook at your GPS position. Updates when you refresh.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if appModel.weather.dailyForecast.isEmpty {
                Text("Forecast loads after location and weather succeed.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(appModel.weather.dailyForecast) { day in
                            dayCard(day)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func dayCard(_ day: DailyForecastDay) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(day.weekdayShort)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(day.dayNumber)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Image(systemName: DailyForecastDay.wmoSymbolName(code: day.weatherCode))
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(height: 28)
            Text(day.highLowFormatted(useFahrenheit: useUS))
                .font(.subheadline.weight(.semibold))
            Text(day.predictionLine)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
        }
        .frame(width: 132, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
        )
    }

    private func formattedOutdoor(fromCelsius c: Double) -> String {
        if useUS {
            let f = c * 9 / 5 + 32
            return String(format: "%.0f°F", f)
        }
        return String(format: "%.1f°C", c)
    }

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: $notificationsEnabled) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Eco alerts")
                        .font(.subheadline.weight(.semibold))
                    Text("Banners when ventilation is ideal or grid carbon is high.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .onChange(of: notificationsEnabled) { _, new in
                EcoNotificationService.shared.notificationsEnabled = new
                if new {
                    Task {
                        _ = await EcoNotificationService.shared.requestAuthorization()
                    }
                }
            }
            if notifications.authorizationStatus == .denied {
                Text("Notifications are off for EcoWeather — enable them in Settings to see alerts.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var recommendation: some View {
        VStack(spacing: 8) {
            Text(appModel.decision?.recommendation ?? "Gathering eco insight…")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var statusRow: some View {
        HStack {
            Label(
                carbonLabel,
                systemImage: "leaf.fill"
            )
            .font(.subheadline)
            Spacer()
            if appModel.carbon.usedFallback {
                Text("Carbon fallback")
                    .font(.caption2)
                    .padding(6)
                    .background(.orange.opacity(0.25))
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var carbonLabel: String {
        guard let d = appModel.decision else { return "Carbon: —" }
        let level: String
        switch d.recommendationLevel {
        case 0: level = "Low"
        case 2: level = "High"
        default: level = "Medium"
        }
        return String(format: "Carbon %@ · %.0f gCO₂eq/kWh", level, d.co2Intensity)
    }

    private var cornerDebugTriggers: some View {
        GeometryReader { geo in
            let s: CGFloat = 72
            Group {
                Color.clear
                    .frame(width: s, height: s)
                    .position(x: s / 2, y: s / 2)
                    .onTapGesture(count: 3) { showDebug = true }
                Color.clear
                    .frame(width: s, height: s)
                    .position(x: geo.size.width - s / 2, y: s / 2)
                    .onTapGesture(count: 3) { showDebug = true }
                Color.clear
                    .frame(width: s, height: s)
                    .position(x: s / 2, y: geo.size.height - s / 2)
                    .onTapGesture(count: 3) { showDebug = true }
                Color.clear
                    .frame(width: s, height: s)
                    .position(x: geo.size.width - s / 2, y: geo.size.height - s / 2)
                    .onTapGesture(count: 3) { showDebug = true }
            }
        }
        .allowsHitTesting(true)
    }
}
