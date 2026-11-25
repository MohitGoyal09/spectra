import SwiftUI
import TidyCore

/// Information TidyRoll lifted out of screenshots (bookings, addresses, events, transit, recipes, orders).
/// It stays here even after the screenshot is deleted.
struct SavedInfoView: View {
    @Environment(AppModel.self) private var model
    @State private var viewer: ViewerContext?
    @State private var toast: Toast?
    @State private var event: EventSheet?

    var body: some View {
        let infos = model.savedInfos
        List {
            ForEach(infos) { entry in
                let live = model.store.items[entry.id] != nil
                HStack(spacing: Space.m) {
                    Group {
                        if live { AssetThumbnail(id: entry.id, side: 70) } else {
                            Palette.fill.overlay(Image(systemName: symbol(entry.info.type)).foregroundStyle(Palette.secondary))
                        }
                    }
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Label(entry.info.title, systemImage: symbol(entry.info.type)).font(.subheadline.weight(.semibold)).lineLimit(2)
                        if let d = entry.info.fields["detail"], !d.isEmpty { Text(d).font(.subheadline).lineLimit(2) }
                        Text(live ? "Screenshot still on this iPhone" : "Screenshot deleted · info kept").font(.caption).foregroundStyle(Palette.secondary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if live { viewer = ViewerContext(ids: [entry.id], start: 0) } }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(live ? .isButton : [])
                .swipeActions(edge: .leading) {
                    if live, model.store.items[entry.id]?.looksLikeEvent == true {
                        Button {
                            Task {
                                switch await model.calendarEvent(for: entry.id) {
                                case .success(let e): event = e
                                case .failure(let err): toast = Toast(symbol: "calendar.badge.exclamationmark", text: err.message)
                                }
                            }
                        } label: { Label("Add to Calendar", systemImage: "calendar.badge.plus") }
                        .tint(Palette.review)
                    }
                }
                .swipeActions {
                    if live {
                        Button(role: .destructive) {
                            Task {
                                if await Gallery.delete([entry.id]) {
                                    await model.forget([entry.id])
                                    toast = Toast(symbol: "checkmark.circle.fill", text: "Screenshot deleted, info kept", tint: Palette.keep)
                                }
                            }
                        } label: { Label("Delete screenshot", systemImage: "trash") }
                    } else {
                        Button(role: .destructive) { model.rules.removeArchived(entry.id); model.scanner.touch() } label: { Label("Remove", systemImage: "xmark") }
                    }
                }
            }
        }
        .navigationTitle("Saved info")
        .overlay {
            if infos.isEmpty {
                ContentUnavailableView("No saved info yet", systemImage: "bookmark",
                                       description: Text("On-device AI picks out bookings, addresses and events from screenshots as it writes titles."))
            }
        }
        .toast($toast)
        .fullScreenCover(item: $viewer) { PhotoViewer(context: $0) }
        .sheet(item: $event) { EventEditor(draft: $0.draft, note: $0.note).ignoresSafeArea() }
    }

    private func symbol(_ type: String) -> String {
        switch type {
        case "booking": "calendar.badge.checkmark"
        case "address": "mappin.and.ellipse"
        case "event": "calendar"
        case "transit": "tram"
        case "recipe": "fork.knife"
        case "order": "bag"
        default: "bookmark"
        }
    }
}
