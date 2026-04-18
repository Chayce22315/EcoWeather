import SwiftUI

/// Frosted “liquid glass” surfaces: layered materials, specular edge, soft shadow.
/// When you build with an SDK that defines `glassEffect`, prefer that for system Liquid Glass.
enum LiquidGlassChrome {
    static let corner: CGFloat = 16

    @ViewBuilder
    static func cardBackground(cornerRadius: CGFloat = corner) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(.ultraThinMaterial)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.55),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.35)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.5)
                .blendMode(.multiply)
        }
        .shadow(color: Color.black.opacity(0.12), radius: 12, y: 6)
    }
}

extension View {
    func liquidGlassCard(cornerRadius: CGFloat = LiquidGlassChrome.corner) -> some View {
        background {
            LiquidGlassChrome.cardBackground(cornerRadius: cornerRadius)
        }
    }
}
