import SwiftUI

/// Proof of the privacy promise: every request that left this iPhone, with the exact text sent. Never photos.
struct PrivacyLogView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var placesOn = Enricher.placesAllowed
    @State private var digestOn = WeeklyDigest.isOn
    @State private var expiryOn = CleanAsYouGo.isOn
    @State private var demoAdded = DemoKit.isAdded
    @State private var demoBusy = false
    @AppStorage("shareAsJPEG") private var shareAsJPEG = false

    var body: some View {
        let entries = model.log.entries.reversed()
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("0").font(.system(.largeTitle, design: .rounded, weight: .bold)) + Text(" photos uploaded").font(.title3.weight(.semibold))
                        Text("\(entries.count) text request\(entries.count == 1 ? "" : "s") to the cloud. Sorting and photo titles run on this iPhone.")
                            .font(.subheadline).foregroundStyle(Palette.secondary)
                    }
                    .padding(.vertical, Space.s)
                }
                Section {
                    Toggle("Cloud help (masked text)", isOn: Binding(get: { model.judge.cloudConsent == true }, set: { model.judge.cloudConsent = $0 }))
                } footer: {
                    Text("Used only when on-device AI can't answer. Gemini gets text with numbers, emails and phone numbers masked. Never photos, never ID or card text.")
                }
                Section {
                    Toggle("Clean as you go", isOn: $expiryOn)
                        .onChange(of: expiryOn) { _, on in
                            Task { expiryOn = await CleanAsYouGo.setOn(on, items: model.snapshot.all) }
                        }
                    Toggle("Weekly digest", isOn: $digestOn)
                        .onChange(of: digestOn) { _, on in
                            Task { digestOn = await WeeklyDigest.setOn(on, summary: WidgetSummary.load() ?? WidgetSummary()) }
                        }
                } footer: { Text("Clean as you go: a note when an OTP screenshot expires or a ticket's date passes; tap it to delete. Weekly digest: a Sunday-morning note with what can go. Both are worked out on this iPhone.") }
                Section {
                    Toggle("Share photos as JPEG", isOn: $shareAsJPEG)
                } footer: { Text("HEIC photos are sent as JPEG, with their date and place, so they open on Windows, Android and websites. Your library keeps the originals.") }
                Section {
                    Toggle("Simulate no on-device AI", isOn: Binding(get: { model.judge.simulateNoOnDevice }, set: { model.judge.simulateNoOnDevice = $0 }))
                    Button(demoBusy ? "Working…" : demoAdded ? "Remove demo photos" : "Add demo photos") {
                        Task {
                            demoBusy = true
                            if demoAdded { _ = await DemoKit.remove() } else { _ = await DemoKit.add() }
                            demoAdded = DemoKit.isAdded; demoBusy = false
                        }
                    }
                    .disabled(demoBusy)
                    .foregroundStyle(demoAdded ? Palette.junk : Palette.review)
                } header: { Text("Demo") } footer: {
                    Text("Shows how Spectra behaves on an iPhone without Apple Intelligence: sorting stays on this iPhone, AI features fall back to Gemini with masked text, and Ask stays off. Demo photos are 13 obviously fake samples (receipts, a ticket, a SAMPLE ID, forwards) in a \u{201C}Spectra Demo\u{201D} album; removing them deletes only that album.")
                }
                Section {
                    Toggle("Place names", isOn: $placesOn)
                        .onChange(of: placesOn) { _, on in
                            Enricher.placesAllowed = on
                            if on { Task { await model.enrich() } }
                        }
                } footer: {
                    Text("Lets you search \u{201C}Goa\u{201D} or \u{201C}Pune\u{201D}. Apple Maps gets one rounded location (about 2 km) per area, never a photo. Each lookup appears below.")
                }
                Section("Requests") {
                    if entries.isEmpty {
                        Text("Nothing has been sent.").foregroundStyle(Palette.secondary)
                    }
                    ForEach(Array(entries.enumerated()), id: \.offset) { _, e in
                        VStack(alignment: .leading, spacing: Space.s) {
                            HStack {
                                Text(e.task.capitalized).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(e.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(Palette.secondary)
                            }
                            Label { Text(e.model).foregroundStyle(Palette.label) } icon: { Image(systemName: "cloud").foregroundStyle(Palette.cloud) }.font(.caption.weight(.medium))
                            Text(e.sentText).font(.caption.monospaced()).foregroundStyle(Palette.secondary).lineLimit(6).textSelection(.enabled)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("Privacy log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}
