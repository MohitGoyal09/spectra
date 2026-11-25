// Scan timing screen (Debug builds only).
import SwiftUI
import Photos
import TidyCore

@MainActor
struct ScanDebugView: View {
    @State private var scanner: Scanner?
    @State private var judge: HybridJudge?
    @State private var limit = 500
    @State private var reportURL: URL?
    @State private var askConsent = false
    @State private var titleSeconds: Double = 0

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    Text("On-device: \(judge.map { "\($0.status)" } ?? "…")")
                    if let s = scanner {
                        ProgressView(value: s.progress) { Text("\(s.done) / \(s.total)") }
                        Text(String(format: "Elapsed %.0f s · %.2f s/photo", s.elapsed, s.elapsed / Double(max(s.done, 1))))
                        Text("Model calls: \(judge?.onDeviceCalls ?? 0) on-device · \(judge?.cloudCalls ?? 0) cloud")
                        if s.titling { Text("Writing titles on-device… \(s.titled) done") }
                    }
                }
                Section("Scan") {
                    Stepper("Limit: \(limit) newest", value: $limit, in: 100...20_000, step: 100)
                    Button("Scan") { Task { await run() } }.disabled(scanner?.running == true)
                    Button("Reset index", role: .destructive) { scanner?.store.reset() }
                    if let reportURL { ShareLink("Share report", item: reportURL) }
                }
                if let s = scanner {
                    Section("Buckets") {
                        ForEach(Bucket.allCases, id: \.self) { b in
                            HStack {
                                Text("\(b)")
                                Spacer()
                                Text("\(s.counts[b] ?? 0) · \(sizeLabel(s.bytesByBucket[b] ?? 0))").monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Spectra scan")
            .alert("Use cloud AI?", isPresented: $askConsent) {
                Button("Send text only") { judge?.cloudConsent = true }
                Button("Rules only", role: .cancel) { judge?.cloudConsent = false }
            } message: {
                Text("This iPhone can't run on-device AI right now. Send text-only descriptions to Gemini? Photos never leave your phone.")
            }
        }
        .task { setUp() }
    }

    private func setUp() {
        guard scanner == nil else { return }
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Spectra", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let j = HybridJudge(log: PrivacyLog(fileURL: dir.appendingPathComponent("privacy-log.json")))
        judge = j
        scanner = Scanner(store: IndexStore(directory: dir), library: PhotoLibraryService(), analyzer: VisionAnalyzer(), judge: j)
        askConsent = j.needsConsent
    }

    private func run() async {
        guard let scanner else { return }
        _ = await PhotoLibraryService().requestAccess()
        reportURL = nil
        await scanner.scan(limit: limit)
        let t0 = Date()
        await scanner.titlePending(limit: 60)
        titleSeconds = Date().timeIntervalSince(t0)
        reportURL = writeReport(scanner)
    }

    private func sizeLabel(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }

    private func writeReport(_ s: Scanner) -> URL {
        var lines = [String(format: "Scanned %d in %.1f s (%.2f s/photo). Model: %d on-device, %d cloud. Status: %@",
                            s.done, s.elapsed, s.elapsed / Double(max(s.done, 1)),
                            judge?.onDeviceCalls ?? 0, judge?.cloudCalls ?? 0, "\(judge?.status ?? .other("?"))")]
        lines.append(String(format: "Titling pass (60 items max): %.1f s, %d titled", titleSeconds, s.titled))
        let stages = s.timer.snapshot.merging((s.analyzerTimer?.snapshot ?? [:]), uniquingKeysWith: +)
        lines.append("Stage seconds (summed across 4 parallel workers): " + stages.sorted { $0.value > $1.value }.map { String(format: "%@ %.1f", $0.key, $0.value) }.joined(separator: " · "))
        for b in Bucket.allCases { lines.append("\(b): \(s.counts[b] ?? 0) · \(sizeLabel(s.bytesByBucket[b] ?? 0))") }
        lines.append("\nSamples (reason | kind | verdict | source | labels | masked text):")
        let byBucket = Dictionary(grouping: s.store.items.values, by: \.bucket)
        for b in Bucket.allCases {
            for i in (byBucket[b] ?? []).prefix(8) {
                let text = TidyCore.mask(String(i.record.ocrText.prefix(60)))
                lines.append("[\(b)] \(i.verdict.reason) | \(i.verdict.kind) | \(i.verdict.verdict) | \(i.verdict.source) | \(i.record.labels.prefix(3).joined(separator: ",")) | \(text)")
            }
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tidyroll-scan.txt")
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
