import SwiftUI

struct DebugMenuView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("electricitymaps_token") private var token: String = ""
    @AppStorage("openweathermap_api_key") private var openWeatherKey: String = ""

    private var buildMetadata: BuildMetadata? {
        BuildMetadata.loadFromBundle()
    }

    private var debugTint: Color {
        guard let raw = buildMetadata?.carbonCommit.uppercased() else {
            return Color.gray
        }
        switch raw {
        case "LOW":
            return Color(red: 0, green: 0.659, blue: 0.420)
        case "HIGH":
            return Color(red: 1, green: 0.298, blue: 0.298)
        case "MEDIUM":
            return Color(red: 1, green: 0.749, blue: 0)
        default:
            return Color.gray
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Electricity Maps token") {
                    SecureField("auth-token", text: $token)
                    Text("Stored in UserDefaults only on-device.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("OpenWeatherMap (optional)") {
                    SecureField("API key", text: $openWeatherKey)
                    Text("If set, live conditions use api.openweathermap.org for your GPS position (°F). Leave empty to use Open-Meteo (no key).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section("Build metadata") {
                    if let meta = buildMetadata {
                        LabeledContent("build_time") { Text(meta.buildTime) }
                        LabeledContent("run_number") { Text("\(meta.runNumber)") }
                        LabeledContent("carbon_commit") { Text(meta.carbonCommit) }
                    } else {
                        Text("build_metadata.json not found in bundle.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Raw values") {
                    LabeledContent("Outdoor °C") { Text(String(format: "%.2f", appModel.lastOutdoor)) }
                    LabeledContent("Humidity %") { Text(String(format: "%.1f", appModel.lastHumidity)) }
                    LabeledContent("CO₂") { Text(String(format: "%.1f", appModel.lastCo2)) }
                    if let err = appModel.weather.lastError {
                        LabeledContent("Weather error") { Text(err) }
                    }
                    if let err = appModel.carbon.lastError {
                        LabeledContent("Carbon error") { Text(err) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(debugTint.opacity(0.15))
            .navigationTitle("Debug")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
