import SwiftUI
import Photos
import MapKit
import VisionKit

/// Presents the system share sheet with the original files, the way Photos does.
/// Files are copied first (no decoding), so every share target receives a real photo or video.
@MainActor enum Sharing {
    /// Returns false when nothing could be exported (for example, offline and only in iCloud).
    static func share(_ ids: [String]) async -> Bool {
        let urls = await Gallery.exportForSharing(ids, asJPEG: UserDefaults.standard.bool(forKey: "shareAsJPEG"))
        guard !urls.isEmpty else { return false }
        present(urls)
        return true
    }

    private static func present(_ urls: [URL]) {
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive }
        guard var top = scene?.keyWindow?.rootViewController else { return }
        while let next = top.presentedViewController { top = next }
        let vc = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        let folder = urls[0].deletingLastPathComponent()
        vc.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: folder) }
        top.present(vc, animated: true)
    }
}

/// Add to Album: existing albums, or a new one.
struct AlbumPickerSheet: View {
    let ids: [String]
    var onDone: (String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var albums: [AlbumInfo] = []
    @State private var newTitle = ""
    @State private var naming = false

    var body: some View {
        NavigationStack {
            List {
                Button { naming = true } label: { Label("New Album…", systemImage: "plus.rectangle.on.rectangle") }
                Section("My Albums") {
                    ForEach(albums) { a in
                        Button { Task { await add(a) } } label: {
                            HStack(spacing: Space.m) {
                                Group {
                                    if let cover = a.coverID { AssetThumbnail(id: cover, side: 120) } else { Palette.fill }
                                }
                                .frame(width: 48, height: 48).clipShape(.rect(cornerRadius: 8))
                                VStack(alignment: .leading) {
                                    Text(a.title).foregroundStyle(Palette.label)
                                    Text("\(a.count)").font(.caption).foregroundStyle(Palette.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Album").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .alert("New Album", isPresented: $naming) {
                TextField("Title", text: $newTitle)
                Button("Cancel", role: .cancel) {}
                Button("Save") { Task { await create() } }.disabled(newTitle.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: { Text("Enter a name for this album.") }
        }
        .task { albums = Gallery.userAlbums() }
    }

    private func add(_ a: AlbumInfo) async {
        let ok = await Gallery.add(ids, toAlbum: a.id)
        onDone(ok ? a.title : nil); dismiss()
    }

    private func create() async {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        let ok = await Gallery.addToAlbum(title: title, ids: ids) != nil
        onDone(ok ? title : nil); dismiss()
    }
}

/// Adjust Date & Time.
struct AdjustDateSheet: View {
    let id: String
    var onDone: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                LabeledContent("Original", value: Gallery.asset(id)?.creationDate?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown")
                DatePicker("Adjusted", selection: $date, in: ...Date()).datePickerStyle(.graphical)
            }
            .navigationTitle("Adjust Date & Time").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adjust") { Task { onDone(await Gallery.setDate(id, date)); dismiss() } }
                }
            }
        }
        .onAppear { date = Gallery.asset(id)?.creationDate ?? Date() }
    }
}

/// Adjust Location: tap the map to move the pin, or remove the location.
struct AdjustLocationSheet: View {
    let id: String
    var onDone: (Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pin: CLLocationCoordinate2D?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        NavigationStack {
            MapReader { proxy in
                Map(position: $camera) { if let pin { Marker("", coordinate: pin) } }
                    .onTapGesture { p in if let c = proxy.convert(p, from: .local) { pin = c } }
            }
            .safeAreaInset(edge: .bottom) {
                Text(pin == nil ? "Tap the map to set a location." : "Tap the map to move the pin.")
                    .font(.footnote).padding(Space.m).glassEffect(.regular, in: Capsule()).padding(Space.m)
            }
            .navigationTitle("Adjust Location").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .bottomBar) {
                    Button("Remove Location", role: .destructive) { Task { onDone(await Gallery.setLocation(id, nil)); dismiss() } }
                        .disabled(Gallery.asset(id)?.location == nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Adjust") {
                        guard let pin else { return }
                        Task { onDone(await Gallery.setLocation(id, CLLocation(latitude: pin.latitude, longitude: pin.longitude))); dismiss() }
                    }
                    .disabled(pin == nil)
                }
            }
        }
        .onAppear {
            guard let c = Gallery.asset(id)?.location?.coordinate else { return }
            pin = c
            camera = .region(MKCoordinateRegion(center: c, latitudinalMeters: 3000, longitudinalMeters: 3000))
        }
    }
}

/// Full-screen slideshow: crossfades every 3 s, tap to pause, Done to exit.
struct SlideshowView: View {
    let ids: [String]
    let start: Int
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    @State private var paused = false
    private static let interval: Duration = .seconds(3)

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if ids.indices.contains(index) {
                AssetThumbnail(id: ids[index], side: 1600, fit: true)
                    .id(ids[index])
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        // Tap-to-pause sits under the controls, so Done always closes the slideshow.
        .contentShape(.rect)
        .onTapGesture { withAnimation { paused.toggle() } }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(paused ? "Resume slideshow" : "Pause slideshow")
        .overlay(alignment: .topTrailing) {
            Button("Done") { dismiss() }.buttonStyle(.glass).padding()
        }
        .overlay(alignment: .bottom) {
            if paused { Label("Paused", systemImage: "pause.fill").font(.footnote).padding(Space.m).glassEffect(.regular, in: Capsule()).padding() }
        }
        .statusBarHidden()
        .task {
            index = start
            UIApplication.shared.isIdleTimerDisabled = true
            defer { UIApplication.shared.isIdleTimerDisabled = false }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.interval)
                guard !paused, !ids.isEmpty else { continue }
                withAnimation(.easeInOut(duration: 0.8)) { index = (index + 1) % ids.count }
            }
        }
    }
}

/// Live Text: select, copy, look up or translate text in a photo (VisionKit, on device).
struct LiveTextImage: UIViewRepresentable {
    let image: UIImage

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView(image: image)
        v.contentMode = .scaleAspectFit
        v.isUserInteractionEnabled = true
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        let interaction = ImageAnalysisInteraction()
        v.addInteraction(interaction)
        Task { @MainActor in
            guard ImageAnalyzer.isSupported,
                  let analysis = try? await ImageAnalyzer().analyze(image, configuration: .init([.text, .machineReadableCode])) else { return }
            interaction.analysis = analysis
            interaction.preferredInteractionTypes = .automatic
            interaction.selectableItemsHighlighted = true
        }
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {}
}
