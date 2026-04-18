import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @ObservedObject private var notifications = EcoNotificationService.shared
    @AppStorage("eco_notifications_enabled") private var notificationsEnabled = true
    @State private var showDetail = false
    @State private var showDebug = false
    @State private var selectedScene: WeatherSceneKind = .live

    private var useUS: Bool { Locale.current.measurementSystem == .us }

    private var liveDerivedScene: WeatherSceneKind {
        guard let w = appModel.weather.lastWeather else { return .live }
        let code = w.wmoWeatherCode ?? 2
        let isDay = w.isDay ?? true
        let precip = w.precipitationMm ?? 0
        return WeatherSceneKind.fromLive(wmoCode: code, isDay: isDay, precipitationMm: precip)
    }

    private var effectiveScene: WeatherSceneKind {
        selectedScene == .live ? liveDerivedScene : selectedScene
    }

    var body: some View {
        ZStack {
            WeatherSkyBackground(scene: effectiveScene)
            skyTintOverlay
            ScrollView {
                VStack(spacing: 20) {
                    weatherSceneTabs
                    heroHeader
                    ForecastCalendarView(days: appModel.weather.dailyForecast, useFahrenheit: useUS)
                        .weatherAtmosphere()
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
                    .weatherAtmosphere()
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            cornerDebugTriggers
        }
        .animation(.easeInOut(duration: 0.55), value: effectiveScene)
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
        .weatherSceneEnvironment(effectiveScene)
    }

    private var skyTintOverlay: some View {
        ZStack {
            LinearGradient(
                colors: [
                    appModel.carbonTintColor().opacity(0.22),
                    Color.clear
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Rectangle()
                .fill(.thinMaterial)
                .opacity(0.35)
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.6), value: appModel.decision?.recommendationLevel ?? -1)
    }

    private var weatherSceneTabs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Sky preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(WeatherSceneKind.allCases) { scene in
                        sceneTabButton(scene)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .padding(12)
        .liquidGlassCard(cornerRadius: 14)
        .weatherAtmosphere()
    }

    private func sceneTabButton(_ scene: WeatherSceneKind) -> some View {
        let on = selectedScene == scene
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                selectedScene = scene
            }
        } label: {
            Text(scene.shortTitle)
                .font(.caption.weight(on ? .semibold : .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    if on {
                        Capsule(style: .continuous)
                            .fill(.thickMaterial)
                    } else {
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.12))
                    }
                }
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.white.opacity(on ? 0.45 : 0.2), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
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
                if selectedScene == .live {
                    Text(liveConditionLine(for: w))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Preview: \(effectiveScene.shortTitle)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
        .padding(16)
        .liquidGlassCard()
        .weatherAtmosphere()
    }

    private func liveConditionLine(for w: CachedWeather) -> String {
        let code = w.wmoWeatherCode
        let isDay = w.isDay
        if let code {
            let headline = DailyForecastDay.wmoHeadline(code: code)
            let dayNight = isDay == false ? "Night" : "Day"
            return "\(headline) · \(dayNight)"
        }
        return "Conditions appear after the next refresh."
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
        .liquidGlassCard()
        .weatherAtmosphere()
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
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.35), lineWidth: 0.75)
            }
            .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
        }
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
        .liquidGlassCard(cornerRadius: 12)
        .weatherAtmosphere()
    }

    private var recommendation: some View {
        VStack(spacing: 8) {
            Text(appModel.decision?.recommendation ?? "Gathering eco insight…")
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
        }
        .padding()
        .liquidGlassCard()
        .weatherAtmosphere()
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
        .liquidGlassCard(cornerRadius: 12)
        .weatherAtmosphere()
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
