import SwiftUI

struct DetailPanelView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Temperature") {
                    LabeledContent("Outdoor") {
                        Text(outdoorFormatted)
                    }
                    LabeledContent("Indoor (assumed)") {
                        Stepper(value: $appModel.indoorCelsius, in: 10 ... 32, step: 0.5) {
                            Text(indoorFormatted)
                        }
                    }
                    LabeledContent("Delta") {
                        Text(deltaFormatted)
                    }
                }

                Section("Humidity") {
                    LabeledContent("Relative humidity") {
                        Text(String(format: "%.0f%%", appModel.lastHumidity))
                    }
                    if appModel.lastHumidity > 60 {
                        Text("Humidity discomfort penalty may apply above 60%.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Grid") {
                    LabeledContent("CO₂ intensity") {
                        Text(String(format: "%.0f gCO₂eq/kWh", appModel.lastCo2))
                    }
                    if let d = appModel.decision {
                        LabeledContent("Action code") {
                            Text("\(d.finalAction)")
                        }
                    }
                }

                if let d = appModel.decision {
                    Section("Guidance") {
                        Text(d.recommendation)
                    }
                }

                if let w = appModel.weather.lastWeather {
                    Section("Freshness") {
                        Text("Weather updated: \(w.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            }
            .navigationTitle("Details")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Apply") {
                        Task { await appModel.refresh() }
                    }
                }
            }
        }
    }

    private var useUS: Bool { Locale.current.measurementSystem == .us }

    private var outdoorFormatted: String { formatTemp(appModel.lastOutdoor) }
    private var indoorFormatted: String { formatTemp(appModel.indoorCelsius) }

    private var deltaFormatted: String {
        if useUS {
            let fOut = appModel.lastOutdoor * 9 / 5 + 32
            let fIn = appModel.indoorCelsius * 9 / 5 + 32
            return String(format: "%.0f°F", fOut - fIn)
        }
        return String(format: "%.1f°C", appModel.lastOutdoor - appModel.indoorCelsius)
    }

    private func formatTemp(_ celsius: Double) -> String {
        if useUS {
            return String(format: "%.0f°F", celsius * 9 / 5 + 32)
        }
        return String(format: "%.1f°C", celsius)
    }
}
