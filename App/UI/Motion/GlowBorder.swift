import SwiftUI

/// What the glow means: spectrum = on-device AI working, amber = cloud call, none = rules only. UI spec §4.
enum GlowState: Equatable { case onDevice, cloud, idle }

func glowState(onDeviceAvailable: Bool, cloudBusy: Bool, working: Bool) -> GlowState {
    if cloudBusy { return .cloud }
    return working && onDeviceAvailable ? .onDevice : .idle
}

/// Rotation of the travelling light; still when Reduce Motion is on.
func glowAngle(time: TimeInterval, lap: TimeInterval, reduceMotion: Bool) -> Angle {
    reduceMotion ? .degrees(-45) : .degrees((time / lap).truncatingRemainder(dividingBy: 1) * 360)
}

/// Ported from Kinetik UI Beam Button (MIT): light runs around the edge with a soft bloom.
struct GlowBorder: ViewModifier {
    let state: GlowState
    let cornerRadius: CGFloat
    var lineWidth: CGFloat = 2
    var bloom: CGFloat = 14
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            if state != .idle {
                TimelineView(.animation(paused: reduceMotion)) { ctx in
                    let angle = glowAngle(time: ctx.date.timeIntervalSinceReferenceDate, lap: state == .cloud ? 1.6 : 3.2, reduceMotion: reduceMotion)
                    let gradient = AngularGradient(colors: state == .cloud ? [Palette.cloud, Palette.cloud.opacity(0.2), Palette.cloud] : Palette.glow,
                                                   center: .center, angle: angle)
                    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    ZStack {
                        shape.strokeBorder(gradient, lineWidth: lineWidth * 3).blur(radius: bloom).opacity(0.6)
                        shape.strokeBorder(gradient, lineWidth: lineWidth)
                    }
                }
                .allowsHitTesting(false)
                .transition(.opacity)
                .accessibilityHidden(true)
            }
        }
        .animation(Motion.smooth, value: state)
    }
}

extension View {
    func glowBorder(_ state: GlowState, cornerRadius: CGFloat) -> some View { modifier(GlowBorder(state: state, cornerRadius: cornerRadius)) }
}

/// Where an AI answer came from: on this iPhone (spectrum) or Gemini with masked text (amber). Shown next to every AI result.
struct AISourceBadge: View {
    let onDevice: Bool
    var body: some View {
        Label {
            Text(onDevice ? "On this iPhone" : "Gemini · masked text").foregroundStyle(Palette.label)
        } icon: {
            Image(systemName: onDevice ? "iphone" : "cloud")
                .foregroundStyle(onDevice ? AnyShapeStyle(LinearGradient(colors: Palette.glow, startPoint: .leading, endPoint: .trailing)) : AnyShapeStyle(Palette.cloud))
        }
            .font(.caption2.weight(.semibold))
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background((onDevice ? Palette.glow[0] : Palette.cloud).opacity(0.12), in: Capsule())
            .accessibilityLabel(onDevice ? "Answered on this iPhone" : "Answered by Gemini from masked text")
    }
}
