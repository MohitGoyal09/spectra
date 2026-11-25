import SwiftUI

/// A small status dot for where AI runs; tap for a tooltip with the privacy facts.
struct AIStatusDot: View {
    @Environment(AppModel.self) private var model
    @State private var showing = false
    @State private var showLog = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var state: (title: String, detail: String, color: Color) {
        let s = model.judge.status
        if s == .available { return ("On-device AI", "Sorting and titles run on this iPhone.", Palette.keep) }
        if model.judge.cloudConsent == true { return ("Cloud fallback", "This iPhone can't run on-device AI, so masked text goes to Gemini.", Palette.cloud) }
        return ("Rules only", "On-device AI is unavailable. Sorting uses rules on this iPhone.", Palette.secondary)
    }

    private var working: Bool { model.scanner.running || model.scanner.titling }

    var body: some View {
        Button { showing = true } label: {
            Circle().fill(state.color).frame(width: 10, height: 10)
                .overlay(Circle().stroke(state.color.opacity(0.35), lineWidth: 6))
                .phaseAnimator([1.0, 1.6], trigger: model.scanner.revision) { v, p in
                    v.overlay(Circle().stroke(state.color.opacity(working && !reduceMotion ? 0.5 / p : 0), lineWidth: 2).scaleEffect(p))
                } animation: { _ in .easeOut(duration: 0.8) }
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.title)
        .accessibilityHint("Shows where AI runs")
        .accessibilityIdentifier("aiStatusDot")
        .sheet(isPresented: $showLog) { PrivacyLogView() }
        .popover(isPresented: $showing, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: Space.s) {
                Label(state.title, systemImage: "circle.fill").labelStyle(DotLabel(color: state.color)).font(.headline)
                Text(state.detail).font(.subheadline).foregroundStyle(Palette.secondary)
                Divider()
                Label("0 photos uploaded", systemImage: "lock.iphone").font(.subheadline)
                Label("\(model.log.entries.count) text request\(model.log.entries.count == 1 ? "" : "s") to the cloud", systemImage: "text.bubble")
                    .font(.subheadline)
                Button { showing = false; DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { showLog = true } } label: {
                    Label("Open privacy log", systemImage: "list.bullet.rectangle")
                }
                .font(.subheadline.weight(.semibold))
            }
            .padding(Space.l)
            .frame(width: 280)
            .presentationCompactAdaptation(.popover)
        }
    }
}

private struct DotLabel: LabelStyle {
    let color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: Space.s) { Circle().fill(color).frame(width: 8, height: 8); configuration.title }
    }
}
