import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @ObservedObject private var notifications = EcoNotificationService.shared
    @AppStorage("eco_notifications_enabled") private var notificationsEnabled = true
    @State private var showDetail = false
    @State private var showDebug = false

    var body: some View {
        ZStack {
            backgroundLayer
            ScrollView {
                VStack(spacing: 24) {
                    header
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
                .padding()
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EcoWeather")
                .font(.largeTitle.bold())
            if let w = appModel.weather.lastWeather {
                HStack {
                    Text(String(format: "%.1f°C outside", w.outdoorCelsius))
                    if appModel.weatherStale {
                        Text("Stale")
                            .font(.caption2)
                            .padding(4)
                            .background(.yellow.opacity(0.3))
                            .clipShape(Capsule())
                    }
                }
                .font(.headline)
            } else {
                Text("Waiting for weather…")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
