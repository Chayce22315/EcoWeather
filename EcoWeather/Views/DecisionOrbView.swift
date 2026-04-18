import SwiftUI

struct DecisionOrbView: View {
    @EnvironmentObject private var appModel: AppViewModel
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            appModel.carbonTintColor().opacity(0.9),
                            appModel.carbonTintColor().opacity(0.2)
                        ],
                        center: .center,
                        startRadius: 10,
                        endRadius: 140
                    )
                )
                .frame(width: 220, height: 220)
                .scaleEffect(pulse ? 1.04 : 0.96)
                .animation(
                    .easeInOut(duration: Double(1.2 - (appModel.decision?.ventilationScore ?? 0.5) * 0.6))
                        .repeatForever(autoreverses: true),
                    value: pulse
                )

            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: 200, height: 200)
                .overlay {
                    VStack(spacing: 8) {
                        Text(scoreText)
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                        Text("Eco score")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
        }
        .onAppear { pulse = true }
        .animation(.easeInOut(duration: 0.6), value: appModel.decision?.recommendationLevel ?? -1)
    }

    private var scoreText: String {
        guard let v = appModel.decision?.ventilationScore else { return "—" }
        return String(format: "%.0f%%", v * 100)
    }
}
