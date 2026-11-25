import SwiftUI

/// Ported from Kinetik UI Slide to Confirm (MIT): drag the knob past 80% (or flick past half) to confirm;
/// light sweeps the track; VoiceOver confirms with the activate action.
struct SlideToConfirm: View {
    let label: String
    let action: () async -> Void
    @State private var offset: CGFloat = 0
    @State private var done = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let knob: CGFloat = 56

    var body: some View {
        GeometryReader { g in
            let track = g.size.width - knob - 8
            ZStack(alignment: .leading) {
                Capsule().fill(Palette.junk.opacity(0.15))
                Capsule().fill(Palette.junk.opacity(0.35)).frame(width: offset + knob + 4)
                if !reduceMotion && !done {
                    TimelineView(.animation) { ctx in
                        let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: 90).offset(x: CGFloat(t) * g.size.width - 45)
                    }
                    .clipShape(Capsule()).allowsHitTesting(false)
                }
                Text(done ? "Done" : label).font(.headline).foregroundStyle(Palette.label).minimumScaleFactor(0.7).frame(maxWidth: .infinity)
                Circle().fill(Palette.junk)
                    .overlay(Image(systemName: done ? "checkmark" : "chevron.right.2").font(.headline).foregroundStyle(.white))
                    .frame(width: knob, height: knob)
                    .padding(4)
                    .offset(x: offset)
                    .gesture(DragGesture()
                        .onChanged { if !done { offset = min(max($0.translation.width, 0), track) } }
                        .onEnded { v in
                            if offset > track * 0.8 || v.predictedEndTranslation.width > track { confirm(track) }
                            else { withAnimation(Motion.snappy) { offset = 0 } }
                        })
            }
        }
        // A fixed height: GeometryReader is greedy, and in a safe-area inset it grew to cover the whole sheet.
        .frame(height: 64)
        .sensoryFeedback(.success, trigger: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { confirm(0) }
    }

    private func confirm(_ track: CGFloat) {
        withAnimation(Motion.snappy) { offset = track; done = true }
        Task {
            await action()
            withAnimation(Motion.snappy) { offset = 0; done = false }
        }
    }
}

struct ResultSummary: Identifiable { let id = UUID(); let freedBytes: Int64; let deleted: Int; let locked: Int }

/// The freed-space moment: rolling figure, confetti, iCloud saving when a cheaper plan now fits.
struct ResultView: View {
    let summary: ResultSummary
    var onDone: () -> Void
    @Environment(AppModel.self) private var model
    @State private var shown = false
    @State private var burst = Date()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: Space.l) {
            Spacer()
            Image(systemName: "checkmark.circle.fill").font(.system(size: 64)).foregroundStyle(Palette.keep)
                .scaleEffect(shown ? 1 : 0.4).opacity(shown ? 1 : 0)
            Text(shown ? "Freed \(gbText(summary.freedBytes))" : "Freed 0 KB").font(.largeTitle.weight(.bold)).contentTransition(.numericText())
                .accessibilityLabel("Freed \(gbText(summary.freedBytes))")
            VStack(spacing: Space.xs) {
                if summary.deleted > 0 { Text("\(summary.deleted) items moved to Recently Deleted for 30 days") }
                if summary.locked > 0 { Text("\(summary.locked) items locked in your Hidden album") }
            }
            .font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            Spacer()
            if summary.freedBytes > 0, let card = FreedCard.image(freedBytes: summary.freedBytes, items: summary.deleted + summary.locked) {
                ShareLink(item: card, preview: SharePreview("Freed \(gbText(summary.freedBytes)) with Spectra", image: card)) {
                    Label("Share", systemImage: "square.and.arrow.up").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glass)
            }
            Button { onDone() } label: { Text("Done").font(.headline).frame(maxWidth: .infinity, minHeight: 50) }.buttonStyle(.glassProminent)
        }
        .padding(Space.xl)
        .background(Palette.background)
        .overlay {
            if !reduceMotion {
                TimelineView(.animation) { ctx in
                    Canvas { g, size in
                        let t = ctx.date.timeIntervalSince(burst)
                        guard t < 2.4 else { return }
                        for i in 0..<80 {
                            let a = Double(i) * 2.399, speed = 170 + Double(i % 9) * 26
                            let x = size.width / 2 + cos(a) * speed * t, y = size.height * 0.32 + sin(a) * speed * t * 0.7 + 280 * t * t
                            g.opacity = max(0, 1 - t / 2.4)
                            g.fill(Path(roundedRect: CGRect(x: x, y: y, width: 7, height: 10), cornerRadius: 2), with: .color(Palette.glow[i % 4]))
                        }
                    }
                }
                .allowsHitTesting(false).ignoresSafeArea()
            }
        }
        .onAppear { burst = Date(); withAnimation(Motion.bouncy.delay(0.1)) { shown = true } }
        .sensoryFeedback(.success, trigger: shown)
    }
}
