import SwiftUI
import TidyCore

/// The scan moment: a dense globe of the user's own photos wears away as each judged photo streams into its folder.
struct ScanView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = ScanStage(folders: Folder.allCases.count)

    enum Folder: Int, CaseIterable {
        case real, duplicates, forwards, screenshots, chats, memes, videos, ids
        var buckets: [Bucket] {
            switch self {
            case .real: [.realPhotos]
            case .duplicates: [.duplicates, .blurry]
            case .forwards: [.forwards]
            case .screenshots: [.otherScreenshots, .expiredScreenshots, .usefulScreenshots]
            case .chats: [.receivedPhotos, .documents]
            case .memes: [.memes, .memesDownloads, .aiMade]
            case .videos: [.bigVideos]
            case .ids: [.idsCards]
            }
        }
        var title: String {
            switch self {
            case .real: "Real photos"
            case .duplicates: "Duplicates"
            case .forwards: "Forwards"
            case .screenshots: "Screenshots"
            case .chats: "From chats"
            case .memes: "Memes & saved"
            case .videos: "Big videos"
            case .ids: "IDs locked"
            }
        }
        var symbol: String { buckets[0].symbol }
        var tint: Color { buckets[0].tint }
        static func of(_ b: Bucket) -> Folder { allCases.first { $0.buckets.contains(b) } ?? .memes }
    }

    @State private var replay: (done: Int, total: Int)?
    private static let space = "scanStage"

    private var progress: (done: Int, total: Int) { replay ?? (model.scanner.done, model.scanner.total) }
    private var finished: Bool { !model.scanner.running && replay == nil && model.scanner.total > 0 }

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.l) {
                header
                globeSlot
                folders
                footer
            }
            .padding(.horizontal, Space.l)
            .padding(.bottom, Space.s)
            .frame(maxHeight: .infinity, alignment: .top)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)   // fixed-layout animation screen: cap text so the footer stays on screen
            .overlay { ScanCanvas(stage: stage, spinning: true) }
            .coordinateSpace(.named(Self.space))
            .background(Palette.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { AIStatusDot() }
            }
        }
        .onPreferenceChange(FolderFrameKey.self) { stage.folderFrames = $0 }
        .onChange(of: model.scanner.revision) { _, _ in
            // Only a running scan feeds the globe. Titling keeps bumping the revision after the scan; feeding the
            // finished scan into a replay emptied the globe at once.
            guard model.scanner.running, replay == nil else { return }
            stage.consume(events: model.scanner.events, done: model.scanner.done, total: model.scanner.total,
                          folderOf: { Folder.of($0).rawValue }, reduceMotion: reduceMotion)
        }
        .onChange(of: finished) { _, isDone in
            guard isDone else { return }
            stage.celebrate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { showKept() }
        }
        .task {
            if model.libraryIDs.isEmpty { await model.loadLibrary() }
            let nothingNew = model.libraryIDs.allSatisfy { model.store.items[$0] != nil }
            if model.hasIndex && nothingNew && !model.scanner.running {
                showKept()                                   // open on the result; the full sort plays only when there is something new
                await model.scan()
            } else {
                await stage.load(ids: model.libraryIDs)
                if !model.scanner.running { await model.scan() }
            }
        }
        .alert("Use cloud AI?", isPresented: Binding(get: { model.askConsent }, set: { model.askConsent = $0 })) {
            Button("Send text only") { model.judge.cloudConsent = true }
            Button("Rules only", role: .cancel) { model.judge.cloudConsent = false }
        } message: {
            Text("This iPhone can't run on-device AI right now. Send text-only descriptions to Gemini? Photos never leave your phone.")
        }
    }

    private var header: some View {
        VStack(spacing: Space.s) {
            HStack(spacing: Space.s) {
                if finished { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.keep).transition(.scale.combined(with: .opacity)) }
                Text(finished ? "\(model.scanner.total.formatted()) sorted" : "Sorting your camera roll").contentTransition(.numericText())
            }
            .font(.title2.weight(.bold))
            Text(finished ? summary : "\(progress.done.formatted()) of \(progress.total.formatted()) · on this iPhone")
                .font(.subheadline).foregroundStyle(Palette.secondary).monospacedDigit().contentTransition(.numericText())
            if !finished {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .tint(Palette.glow[0]).frame(maxWidth: 220)
            }
        }
        .animation(Motion.smooth, value: progress.done)
        .animation(Motion.bouncy, value: finished)
        .frame(maxWidth: .infinity)
    }

    private var summary: String {
        let safe = model.freeableBytes, review = model.reviewBytes
        if safe == 0 && review == 0 { return "Nothing needs clearing" }
        return "\(gbText(safe)) safe to clear · \(gbText(review)) worth a look"
    }

    private var globeSlot: some View {
        VStack(spacing: Space.s) {
            Circle()
                .fill(Palette.fill.opacity(0.35))
                .glowBorder(model.scanner.running || model.scanner.titling || replay != nil ? model.glow : .idle, cornerRadius: 150)
                .frame(width: 280, height: 280)
                .background(GeometryReader { g in
                    Color.clear
                        .onAppear { stage.globeFrame = g.frame(in: .named(Self.space)) }
                        .onChange(of: g.frame(in: .named(Self.space))) { _, f in stage.globeFrame = f }
                })
            if stage.kept && finished {
                Label("\(model.realCount.formatted()) real photos kept · nothing uploaded", systemImage: "heart")
                    .font(.footnote).foregroundStyle(Palette.secondary)
                    .transition(.opacity)
            }
        }
        .animation(Motion.smooth, value: stage.kept)
    }

    /// The photos that stay: the globe re-forms from real photos, and folders show their covers.
    private func showKept() {
        stage.reform(ids: model.items(in: .realPhotos).map(\.record.id))
        var byFolder: [Int: [String]] = [:]
        for f in Folder.allCases { byFolder[f.rawValue] = f.buckets.flatMap { model.items(in: $0).prefix(3).map(\.record.id) } }
        stage.fillStrips(byFolder)
    }

    private var folders: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.s), GridItem(.flexible(), spacing: Space.s)], spacing: Space.s) {
            ForEach(Folder.allCases, id: \.self) { folder in
                let count = folder.buckets.map { model.count($0) }.reduce(0, +)
                HStack(spacing: Space.s) {
                    cover(folder)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(folder.title).font(.footnote.weight(.semibold)).lineLimit(2).minimumScaleFactor(0.8)
                        Text(count.formatted()).font(.caption).foregroundStyle(Palette.secondary).monospacedDigit().contentTransition(.numericText())
                    }
                    Spacer(minLength: 0)
                }
                .padding(Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .background(GeometryReader { g in Color.clear.preference(key: FolderFrameKey.self, value: [folder.rawValue: g.frame(in: .named(Self.space))]) })
                .animation(Motion.snappy, value: count)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("\(folder.title), \(count)")
            }
        }
    }

    /// A small fanned stack: the latest photos that landed here.
    private func cover(_ folder: Folder) -> some View {
        let images = stage.strips[folder.rawValue].suffix(3)
        return ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.fill)
            Image(systemName: folder.symbol).font(.footnote).foregroundStyle(folder.tint).opacity(images.isEmpty ? 1 : 0)
            ForEach(Array(images.enumerated()), id: \.offset) { i, img in
                Image(decorative: img, scale: 1).resizable().scaledToFill()
                    .frame(width: 40, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .rotationEffect(.degrees(Double(i - images.count + 1) * 7))
                    .blur(radius: folder == .ids ? 5 : 0)
                    .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            }
        }
        .frame(width: 44, height: 44)
    }

    /// Nothing new to scan: replay the existing sort so the globe still distributes into the folders.
    private func playExisting() async {
        await stage.load(ids: model.libraryIDs)
        try? await Task.sleep(for: .milliseconds(600))
        let items = model.store.items.values.sorted { $0.record.createdAt > $1.record.createdAt }
        let events = items.map { (id: $0.record.id, bucket: $0.bucket) }
        replay = (0, events.count)
        let step = max(1, events.count / 120)
        var i = 0
        while i < events.count {
            i = min(i + step, events.count)
            replay = (i, events.count)
            stage.consume(events: Array(events.prefix(i)), done: i, total: events.count, folderOf: { Folder.of($0).rawValue }, reduceMotion: reduceMotion)
            try? await Task.sleep(for: .milliseconds(90))
        }
        try? await Task.sleep(for: .seconds(1))
        replay = nil
        stage.celebrate()
        showKept()
    }

    private var footer: some View {
        VStack(spacing: Space.s) {
            if model.scanner.titling {
                Label("Writing titles with on-device AI", systemImage: "sparkles").font(.footnote).foregroundStyle(Palette.secondary)
            }
            if finished {
                Button { model.tab = .cleanUp; dismiss() } label: {
                    Text("Review what can go").font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.glassProminent)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            HStack {
                Label("0 photos uploaded", systemImage: "lock.iphone")
                if finished {
                    Spacer()
                    Button { Task { await playExisting() } } label: { Label("Replay", systemImage: "play.circle") }
                        .disabled(replay != nil)
                }
            }
            .font(.footnote).foregroundStyle(Palette.secondary)
        }
        .animation(Motion.smooth, value: finished)
    }
}

private struct FolderFrameKey: PreferenceKey {
    static let defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) { value.merge(nextValue(), uniquingKeysWith: { $1 }) }
}
