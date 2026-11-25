import SwiftUI

/// Pressable cards and tiles: a quick spring press-in, like Photos' collection tiles.
struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.9 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Glass toast at the top that confirms an action and dismisses itself.
struct Toast: Equatable { let symbol: String; let text: String; var tint: Color = Palette.label; let id = UUID() }

struct ToastHost: ViewModifier {
    @Binding var toast: Toast?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let toast {
                Label { Text(toast.text).foregroundStyle(Palette.label) } icon: { Image(systemName: toast.symbol).foregroundStyle(toast.tint) }
                    .font(.subheadline.weight(.semibold))
                    .symbolEffect(.bounce, value: reduceMotion ? nil : toast.id)
                    .padding(.horizontal, Space.l).padding(.vertical, Space.m)
                    .glassEffect(.regular, in: Capsule())
                    .padding(.top, Space.s)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: toast.id) {
                        AccessibilityNotification.Announcement(toast.text).post()
                        try? await Task.sleep(for: .seconds(3))
                        withAnimation(Motion.smooth) { self.toast = nil }
                    }
                    .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : Motion.bouncy, value: toast)
        .sensoryFeedback(.success, trigger: toast?.id)
    }
}

extension View {
    func toast(_ toast: Binding<Toast?>) -> some View { modifier(ToastHost(toast: toast)) }
}
