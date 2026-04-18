import SwiftUI

@main
struct EcoWeatherApp: App {
    @StateObject private var appModel = AppViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(appModel)
        }
    }
}
