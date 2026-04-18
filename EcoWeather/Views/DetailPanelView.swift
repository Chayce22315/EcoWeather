import SwiftUI

struct DetailPanelView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Temperature") {
                    LabeledContent("Outdoor") {
                        Text(String(format: "%.1f°C", appModel.lastOutdoor))
                    }
                    LabeledContent("Indoor (assumed)") {
                        Stepper(value: $appModel.indoorCelsius, in: 10 ... 32, step: 0.5) {
                            Text(String(format: "%.1f°C", appModel.indoorCelsius))
                        }
                    }
                    LabeledContent("Delta") {
                        Text(String(format: "%.1f°C", appModel.lastOutdoor - appModel.indoorCelsius))
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
}
