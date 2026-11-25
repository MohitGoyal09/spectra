import SwiftUI
import TidyCore

/// "Albums from one sentence": Gemini turns the sentence into a rule (it sees only the masked sentence),
/// this iPhone applies it to every photo and keeps the album up to date.
struct SmartAlbumSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sentence = ""
    @State private var spec: RuleSpec?
    @State private var compiling = false
    @State private var error: String?
    @State private var saving = false
    @State private var ruleOnDevice = true
    @FocusState private var focused: Bool
    private let examples = ["Photos of my dog", "Bills and receipts go to Tax 2026", "Food photos from this year", "Screenshots from last month"]

    var body: some View {
        let ids = spec.map { model.matching($0) } ?? []
        NavigationStack {
            List {
                Section {
                    TextField("Describe an album…", text: $sentence, axis: .vertical)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { Task { await compile() } }
                        .padding(Space.s)
                        .glowBorder(compiling ? (model.judge.status == .available ? .onDevice : .cloud) : .idle, cornerRadius: 12)
                    if spec == nil {
                        ForEach(examples, id: \.self) { e in
                            Button { sentence = e; Task { await compile() } } label: { Label(e, systemImage: "text.quote").font(.subheadline) }
                        }
                    }
                } footer: {
                    Text("Understood on this iPhone. Only if on-device AI is unavailable and you allowed cloud help, Gemini gets this sentence with numbers masked. Your photos never leave this iPhone.")
                }
                if let error { Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Palette.junk) } }
                if let spec {
                    Section("Rule") {
                        LabeledContent("Album", value: spec.name)
                        RuleChips(spec: spec)
                        AISourceBadge(onDevice: ruleOnDevice)
                    }
                    Section {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 4), spacing: 2) {
                            ForEach(ids.prefix(16), id: \.self) { id in
                                Color.clear.aspectRatio(1, contentMode: .fit).overlay(AssetThumbnail(id: id, side: 90)).clipped()
                            }
                        }
                        .listRowInsets(EdgeInsets())
                    } header: { Text("\(ids.count) photos match") } footer: {
                        Text(ids.isEmpty ? "None yet. New photos that match are added on their own." : "New photos that match are added on their own.")
                    }
                }
            }
            .navigationTitle("New smart album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    if spec == nil {
                        Button("Next") { Task { await compile() } }.disabled(sentence.count < 3 || compiling)
                    } else {
                        Button("Save") { Task { await save(ids) } }.disabled(saving || spec?.name.isEmpty == true).bold()
                    }
                }
            }
            .onAppear { focused = true }
        }
    }

    private func compile() async {
        guard sentence.count >= 3 else { return }
        compiling = true; error = nil
        defer { compiling = false }
        do { spec = model.relaxed(try await model.judge.compileRule(sentence, labels: model.snapshot.labels)); ruleOnDevice = model.judge.lastOnDevice }
        catch { self.error = "Couldn't read that sentence. Try simpler words." }
    }

    private func save(_ ids: [String]) async {
        guard let spec else { return }
        saving = true
        let rule = SavedRule(sentence: sentence, spec: spec)
        model.rules.add(rule)
        model.rules.setAlbum(rule.id, await Gallery.addToAlbum(title: spec.name, ids: ids))
        model.scanner.touch()
        dismiss()
        // Photos not sorted yet can't match: sort them now; the album fills as the scan ends.
        if model.libraryIDs.contains(where: { model.store.items[$0] == nil }) { Task { await model.scan() } }
    }
}

/// The rule's fields as readable chips.
struct RuleChips: View {
    let spec: RuleSpec
    var body: some View {
        let f = spec.include
        let df = Date.FormatStyle(date: .abbreviated, time: .omitted)
        let chips: [String] = (f.kinds ?? []).map { "\($0.rawValue.capitalized)" } + (f.docTypes ?? []).map { $0.rawValue.capitalized }
            + (f.junkTypes ?? []).map { $0.rawValue.replacingOccurrences(of: "_", with: " ").capitalized }
            + (f.labels ?? []).map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
            + (f.keywords ?? []).map { "\u{201C}\($0)\u{201D}" }
            + [f.dateFrom.map { "From \($0.formatted(df))" }, f.dateTo.map { "To \($0.formatted(df))" }].compactMap { $0 }
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.s) {
                ForEach(chips, id: \.self) { Text($0).font(.footnote.weight(.medium)).padding(.horizontal, 10).padding(.vertical, 5).background(Palette.fill, in: Capsule()) }
            }
        }
    }
}
