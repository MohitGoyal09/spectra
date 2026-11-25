import SwiftUI
import TidyCore

/// Search over the on-device index: titles, reasons, text read from photos, collections and months. Nothing leaves the phone.
struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var viewer: ViewerContext?
    @State private var selection: Set<String>?
    @Namespace private var zoom

    @State private var results: [String] = []
    /// What the on-device model understood the query as; its matches replace the word matches when it finds any.
    @State private var understood: RuleSpec?
    @State private var thinking = false
    @State private var answer: AskResult?
    @State private var understoodOnDevice = true
    @State private var toast: Toast?

    typealias Row = (id: String, date: Date, text: String, scores: [String: Float])

    /// Ranked search: word matches (written text 1, labels by confidence) plus picture search (how the photo looks).
    /// Photos found both ways lead; ties go to the newest.
    nonisolated private static func search(_ q: String, in rows: [Row], picture: [String: Float]) -> [String] {
        var score: [String: Float] = [:]
        for r in rows {
            let words = searchScore(q, text: r.text, labelScores: r.scores)
            let look = picture[r.id].map { ($0 - 0.2) * 10 }        // ~0-2
            // Photos with every word written in them (or labelled) always rank above picture-only matches.
            if words != nil || look != nil { score[r.id] = (words.map { 10 + $0 } ?? 0) + (look ?? 0) }
        }
        return rows.filter { score[$0.id] != nil }
            .sorted { (score[$0.id]!, $0.date) > (score[$1.id]!, $1.date) }.map(\.id)
    }

    private func runSearch(_ query: String) async {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        understood = nil; thinking = false; answer = nil
        guard q.count >= 2 else { results = []; return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        let rows: [Row] = model.snapshot.all.map { i in
            (id: i.record.id, date: i.record.createdAt, text: [i.verdict.reason, i.bucket.title, i.record.ocrText, i.record.labels.joined(separator: " "), i.record.place ?? "",
                f.string(from: i.record.createdAt), i.verdict.savedInfo?.title ?? "",
                i.verdict.docType.map { "\($0.rawValue) \($0 == .receipt || $0 == .bill ? "receipts bills" : "")" } ?? "",
                i.verdict.sensitive == nil ? "" : "id ids card cards"].joined(separator: " ").lowercased(),
             scores: i.record.labelScores ?? [:])
        }
        let picture = isQuestion(q) ? [:] : (model.pictureMatches(q) ?? [:])
        let found = await Task.detached(priority: .userInitiated) { Self.search(q, in: rows, picture: picture) }.value
        guard !Task.isCancelled else { return }
        results = found
        if isQuestion(q) { await ask(q, wordHits: found) } else { await understand(q, wordHits: found.count) }
    }

    /// AI-native step: a sentence ("dog photos from last summer", "bills from Swiggy") becomes a rule on this iPhone.
    /// Runs for multi-word queries, or when plain words found nothing.
    private func understand(_ q: String, wordHits: Int) async {
        guard q.split(separator: " ").count >= 2 || wordHits == 0 else { return }
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        thinking = true
        defer { thinking = false }
        guard let raw = try? await model.judge.compileRule(q, labels: model.snapshot.labels),
              !Task.isCancelled else { return }
        let spec = model.relaxed(raw)
        let ids = model.matching(spec)
        let rule = Set(ids)
        // The understood rule's photos lead; earlier word and picture matches stay below them.
        understoodOnDevice = model.judge.lastOnDevice
        withAnimation(Motion.smooth) { understood = spec; results = ids + results.filter { !rule.contains($0) } }
    }

    /// Ask your photos: retrieval and the answer both run on this iPhone; the source photos lead the results.
    private func ask(_ q: String, wordHits: [String]) async {
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        thinking = true
        defer { thinking = false }
        let r = try? await model.judge.ask(q, items: model.snapshot.all)
        guard !Task.isCancelled else { return }
        let a = r ?? AskResult(answer: "I couldn't find that in your photos.", sourceIDs: [], onDevice: true)
        AccessibilityNotification.Announcement(a.answer).post()
        withAnimation(Motion.smooth) {
            answer = a
            results = a.sourceIDs + wordHits.filter { !a.sourceIDs.contains($0) }
        }
    }

    private func saveAsAlbum(_ spec: RuleSpec) async {
        let rule = SavedRule(sentence: query, spec: spec)
        model.rules.add(rule)
        let album = await Gallery.addToAlbum(title: spec.name, ids: model.matching(spec))
        model.rules.setAlbum(rule.id, album)
        model.scanner.touch()
        toast = album == nil ? Toast(symbol: "exclamationmark.triangle", text: "Couldn't create the album", tint: Palette.junk)
                             : Toast(symbol: "rectangle.stack.badge.plus", text: "Saved as \u{201C}\(spec.name)\u{201D}. New matches join on their own.", tint: Palette.keep)
    }

    /// Suggestions from the on-device index: only what this library actually has.
    private var suggestions: [(String, String, String)] {
        var out: [(String, String, String)] = [
            ("What's my Wi-Fi password?", "questionmark.bubble", "What's my wifi password?"),
            ("When is my next flight?", "questionmark.bubble", "When is my next flight?"),
        ]
        let items = model.store.items.values
        if items.contains(where: { $0.verdict.docType == .receipt || $0.verdict.docType == .bill }) { out.append(("Receipts & bills", "doc.text", "receipt")) }
        if items.contains(where: { $0.verdict.sensitive != nil }) { out.append(("IDs & cards", "lock", "ids")) }
        if model.count(.otherScreenshots) > 0 { out.append(("Screenshots", "camera.viewfinder", "screenshot")) }
        if model.count(.receivedPhotos) > 0 { out.append(("From chats", "bubble.left.and.text.bubble.right", "from chats")) }
        if model.count(.documents) > 0 { out.append(("Documents", "doc.richtext", "document")) }
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        for m in Set(items.map { f.string(from: $0.record.createdAt) }).sorted(by: { (f.date(from: $0) ?? .distantPast) > (f.date(from: $1) ?? .distantPast) }).prefix(3) {
            out.append((m, "calendar", m.lowercased()))
        }
        return out
    }

    var body: some View {
        let ids = results
        NavigationStack {
            ScrollView {
                if model.enricher.running && model.enricher.total > 0 {
                    Label("Making photos searchable on this iPhone… \(model.enricher.done) of \(model.enricher.total)", systemImage: "sparkle.magnifyingglass")
                        .font(.footnote).foregroundStyle(Palette.secondary).contentTransition(.numericText())
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.l)
                }
                if isQuestion(query) && (thinking || answer != nil) { answerCard.padding(.horizontal, Space.l) }
                else if thinking || understood != nil { understoodBar.padding(.horizontal, Space.l) }
                if !ids.isEmpty {
                    Text("\(ids.count.formatted()) results").font(.footnote).foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Space.l)
                    PhotoGrid(ids: ids, sectioned: false, selection: $selection, zoomNamespace: zoom) { viewer = ViewerContext(ids: ids, start: $0) }
                }
            }
            .background(Palette.background)
            .navigationTitle("Search")
            .searchable(text: $query, prompt: "Dog at the beach, or ask a question…")
            .searchSuggestions {
                if query.isEmpty {
                    ForEach(suggestions, id: \.0) { title, symbol, q in
                        Label(title, systemImage: symbol).searchCompletion(q)
                    }
                }
            }
            .overlay {
                if query.count < 2 {
                    ContentUnavailableView("Search your photos", systemImage: "magnifyingglass",
                                           description: Text("Type words, a sentence or a question like \u{201C}What's my Wi-Fi password?\u{201D}. Spectra answers on this iPhone from what's in your photos."))
                } else if ids.isEmpty && !thinking && answer == nil {
                    ContentUnavailableView.search(text: query)
                }
            }
            .task(id: query) { await runSearch(query) }
            .toast($toast)
            .fullScreenCover(item: $viewer) { ctx in
            PhotoViewer(context: ctx).navigationTransition(.zoom(sourceID: ctx.ids[ctx.start], in: zoom))
        }
        }
    }
}

private extension SearchView {
    /// "Understood as" row: the rule the on-device model made, with a one-tap Save as album.
    @ViewBuilder var understoodBar: some View {
        HStack(spacing: Space.s) {
            Image(systemName: "sparkles").foregroundStyle(Palette.glow[0])
            if let understood {
                AISourceBadge(onDevice: understoodOnDevice)
                RuleChips(spec: understood)
                Button("Save as album") { Task { await saveAsAlbum(understood) } }
                    .font(.footnote.weight(.semibold)).buttonStyle(.glass)
            } else {
                Text(model.judge.status == .available ? "Understanding on this iPhone…" : "Asking Gemini with masked text…")
                    .font(.footnote).foregroundStyle(Palette.secondary)
                Spacer()
            }
        }
        .padding(Space.s)
        .glowBorder(understood != nil ? .idle : model.judge.status == .available ? .onDevice : .cloud, cornerRadius: 12)
        .transition(.opacity)
    }
}

private extension SearchView {
    /// Answer card: the on-device model's answer, the photos it came from, and where it ran.
    @ViewBuilder var answerCard: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label(answer == nil ? "Looking through your photos…" : "Answer", systemImage: "sparkles")
                .font(.footnote.weight(.semibold)).foregroundStyle(Palette.glow[1])
            if let answer {
                Text(answer.answer).font(.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                if !answer.sourceIDs.isEmpty {
                    HStack(spacing: Space.s) {
                        ForEach(answer.sourceIDs.prefix(4), id: \.self) { id in
                            Button { viewer = ViewerContext(ids: answer.sourceIDs, start: answer.sourceIDs.firstIndex(of: id) ?? 0) } label: {
                                Color.clear.frame(width: 56, height: 56)
                                    .overlay(AssetThumbnail(id: id, side: 112)).clipShape(.rect(cornerRadius: Radius.thumb))
                            }
                            .accessibilityLabel("Open source photo")
                        }
                    }
                }
                AISourceBadge(onDevice: answer.onDevice)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.l)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        .glowBorder(answer == nil ? .onDevice : .idle, cornerRadius: Radius.card)
        .transition(.opacity)
    }
}
