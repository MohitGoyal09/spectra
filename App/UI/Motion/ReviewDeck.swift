import SwiftUI
import TidyCore

/// Ported from Kinetik UI Deckfall (MIT): swipe left to delete, right to keep, up to lock; buttons for every action;
/// undo; decisions apply together at the end (deletes show the iOS confirmation).
struct ReviewDeck: View {
    let ids: [String]
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var drag: CGSize = .zero
    @State private var decisions: [(id: String, action: Action)] = []
    @State private var result: ResultSummary?

    enum Action { case delete, keep, lock
        var label: String { switch self { case .delete: "DELETE"; case .keep: "KEEP"; case .lock: "LOCK" } }
        var color: Color { switch self { case .delete: Palette.junk; case .keep: Palette.keep; case .lock: Palette.locked } }
    }

    private var pending: Action? {
        if drag.height < -110 && abs(drag.height) > abs(drag.width) { return .lock }
        if drag.width < -100 { return .delete }
        if drag.width > 100 { return .keep }
        return nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.l) {
                if index < ids.count {
                    ZStack {
                        ForEach(Array(ids.enumerated().filter { $0.offset >= index && $0.offset < index + 3 }.reversed()), id: \.element) { i, id in
                            card(id, depth: i - index)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    buttons
                } else {
                    finish.frame(maxHeight: .infinity)
                }
            }
            .padding(Space.l)
            .background(Palette.grouped)
            .navigationTitle(index < ids.count ? "\(index + 1) of \(ids.count)" : "Done")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { undo() } label: { Label("Undo", systemImage: "arrow.uturn.backward") }.disabled(decisions.isEmpty)
                }
            }
            .fullScreenCover(item: $result) { ResultView(summary: $0) { dismiss() } }
        }
    }

    private func card(_ id: String, depth: Int) -> some View {
        let top = depth == 0
        let item = model.store.items[id]
        return VStack(spacing: 0) {
            AssetThumbnail(id: id, side: 600).aspectRatio(3 / 4, contentMode: .fit).clipped()
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item?.verdict.reason ?? "").font(.headline).lineLimit(2)
                    Text("\(item?.bucket.title ?? "") · \(gbText(item?.record.fileBytes ?? 0))").font(.subheadline).foregroundStyle(Palette.secondary)
                }
                Spacer()
            }
            .padding(Space.l)
            .background(Palette.card)
        }
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .topLeading) {
            if top, let p = pending {
                Text(p.label).font(.title.weight(.heavy)).foregroundStyle(p.color)
                    .padding(.horizontal, Space.m).padding(.vertical, Space.xs)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(p.color, lineWidth: 3))
                    .rotationEffect(.degrees(-12)).padding(Space.xl)
            }
        }
        .shadow(color: .black.opacity(top ? 0.18 : 0.08), radius: 14, y: 8)
        .scaleEffect(1 - CGFloat(depth) * 0.05)
        .offset(y: CGFloat(depth) * 14)
        .offset(top ? drag : .zero)
        .rotationEffect(.degrees(top && !reduceMotion ? Double(drag.width) / 18 : 0))
        .gesture(top ? DragGesture()
            .onChanged { drag = $0.translation }
            .onEnded { v in
                if let p = pending { decide(p, velocity: v.predictedEndTranslation) } else { withAnimation(Motion.snappy) { drag = .zero } }
            } : nil)
        .accessibilityElement(children: .combine)
        .accessibilityActions {
            Button("Delete") { decide(.delete) }
            Button("Keep") { decide(.keep) }
            Button("Lock") { decide(.lock) }
        }
        .sensoryFeedback(.selection, trigger: pending != nil)
        .accessibilityHidden(depth != 0)   // only the top card is read
    }

    private var buttons: some View {
        HStack(spacing: Space.xxl) {
            round("trash", Palette.junk, "Delete") { decide(.delete) }
            round("lock", Palette.locked, "Lock") { decide(.lock) }
            round("heart", Palette.keep, "Keep") { decide(.keep) }
        }
    }

    private func round(_ symbol: String, _ color: Color, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.title2.weight(.semibold)).foregroundStyle(color).frame(width: 60, height: 60) }
            .buttonStyle(.glass).clipShape(Circle()).accessibilityLabel(label)
    }

    private func decide(_ a: Action, velocity: CGSize = .zero) {
        guard index < ids.count else { return }
        let fly: CGSize = switch a { case .delete: CGSize(width: -700, height: velocity.height / 3); case .keep: CGSize(width: 700, height: velocity.height / 3); case .lock: CGSize(width: 0, height: -900) }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Motion.snappy) { drag = reduceMotion ? .zero : fly }
        decisions.append((ids[index], a))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { index += 1; drag = .zero }
    }

    private func undo() {
        guard !decisions.isEmpty else { return }
        decisions.removeLast()
        withAnimation(Motion.smooth) { index = max(index - 1, 0); drag = .zero }
    }

    private var toDelete: [String] { decisions.filter { $0.action == .delete }.map(\.id) }
    private var toLock: [String] { decisions.filter { $0.action == .lock }.map(\.id) }
    private var deleteBytes: Int64 { toDelete.compactMap { model.store.items[$0]?.record.fileBytes }.reduce(0, +) }

    private var finish: some View {
        VStack(spacing: Space.l) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(Palette.keep)
            Text("Reviewed \(decisions.count) items").font(.title2.weight(.bold))
            Text("\(toDelete.count) to delete (\(gbText(deleteBytes))) · \(toLock.count) to lock · \(decisions.count - toDelete.count - toLock.count) kept")
                .font(.subheadline).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            if !toDelete.isEmpty || !toLock.isEmpty {
                SlideToConfirm(label: toDelete.isEmpty ? "Slide to lock \(toLock.count)" : "Slide to free \(gbText(deleteBytes))") { await apply() }
            } else {
                Button("Done") { model.keep(decisions.map(\.id)); dismiss() }.buttonStyle(.glassProminent)
            }
        }
    }

    private func apply() async {
        model.keep(decisions.filter { $0.action == .keep }.map(\.id))
        if !toLock.isEmpty, await Gallery.hide(toLock) { await model.forget(toLock) }
        let deleted = toDelete.isEmpty ? false : await Gallery.delete(toDelete)
        if deleted { await model.forget(toDelete) }
        result = ResultSummary(freedBytes: deleted ? deleteBytes : 0, deleted: deleted ? toDelete.count : 0, locked: toLock.count)
    }
}
