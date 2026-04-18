import Combine
import Foundation
import UserNotifications

enum EcoNotificationCategory {
    static let general = "ECO_ALERT"
}

@MainActor
final class EcoNotificationService: NSObject, ObservableObject {
    static let shared = EcoNotificationService()

    /// Matches `@AppStorage` key in `DashboardView` for the notifications toggle.
    static let notificationsEnabledStorageKey = "eco_notifications_enabled"

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    private enum Keys {
        static let lastVentilationAlertAt = "eco_last_ventilation_alert_at"
        static let lastHighCarbonAlertAt = "eco_last_high_carbon_alert_at"
    }

    private let minIntervalBetweenSameKind: TimeInterval = 4 * 60 * 60

    var notificationsEnabled: Bool {
        get { defaults.object(forKey: Self.notificationsEnabledStorageKey) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Self.notificationsEnabledStorageKey) }
    }

    override private init() {
        super.init()
    }

    func registerDelegate() {
        center.delegate = self
        registerCategories()
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            await refreshAuthorizationStatus()
            return false
        }
    }

    private func registerCategories() {
        let ecoAlert = UNNotificationCategory(
            identifier: EcoNotificationCategory.general,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([ecoAlert])
    }

    func evaluateDecisionChange(previous: EcoDecisionModel?, current: EcoDecisionModel?) {
        guard notificationsEnabled else { return }
        guard authorizationStatus == .authorized else { return }
        guard let current else { return }
        guard previous != nil else { return }

        if current.recommendationLevel == 2, previous?.recommendationLevel != 2 {
            scheduleHighCarbon(body: current.recommendation)
        }

        let ventOpportunity = current.finalAction == 1 && current.ventilationScore > 0.7
        let wasVent = (previous?.finalAction == 1) && ((previous?.ventilationScore ?? 0) > 0.7)
        if ventOpportunity, !wasVent {
            scheduleVentilation(body: current.recommendation)
        }
    }

    private func scheduleHighCarbon(body: String) {
        guard shouldFire(key: Keys.lastHighCarbonAlertAt) else { return }
        schedule(
            title: "High grid carbon",
            subtitle: "Delay heavy energy use if you can",
            body: body,
            category: EcoNotificationCategory.general
        )
        touch(key: Keys.lastHighCarbonAlertAt)
    }

    private func scheduleVentilation(body: String) {
        guard shouldFire(key: Keys.lastVentilationAlertAt) else { return }
        schedule(
            title: "Ventilation opportunity",
            subtitle: "EcoWeather",
            body: body,
            category: EcoNotificationCategory.general
        )
        touch(key: Keys.lastVentilationAlertAt)
    }

    private func shouldFire(key: String) -> Bool {
        let last = defaults.double(forKey: key)
        if last == 0 { return true }
        return Date().timeIntervalSince1970 - last >= minIntervalBetweenSameKind
    }

    private func touch(key: String) {
        defaults.set(Date().timeIntervalSince1970, forKey: key)
    }

    private func schedule(title: String, subtitle: String?, body: String, category: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        if let subtitle {
            content.subtitle = subtitle
        }
        content.body = body.isEmpty ? "Open EcoWeather for details." : body
        content.sound = .default
        content.categoryIdentifier = category
        if #available(iOS 15.0, *) {
            content.interruptionLevel = .active
        }

        let id = UUID().uuidString
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                #if DEBUG
                print("EcoNotificationService: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

extension EcoNotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }
}
