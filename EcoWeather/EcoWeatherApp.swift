import SwiftUI

@main
struct EcoWeatherApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(appModel)
        }
    }
}
