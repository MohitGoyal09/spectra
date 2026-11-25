import SwiftUI

/// Apple Photos layout: Library and Collections, plus TidyRoll's Clean Up, and Search as its own round button.
struct RootView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Library", systemImage: "photo.on.rectangle", value: AppTab.library) { HomeView() }
            Tab("Collections", systemImage: "square.stack", value: AppTab.collections) { CollectionsView() }
            Tab("Clean Up", systemImage: "sparkles", value: AppTab.cleanUp) { CleanUpView() }
            #if DEBUG
            if !FilmScope.isOn {        // film mode shows the app as users get it
                Tab("Debug", systemImage: "ladybug", value: AppTab.debug) { ScanDebugView() }
            }
            #endif
            Tab(value: AppTab.search, role: .search) { SearchView() }
        }
        .onOpenURL { url in if url.host == "cleanup" { model.tab = .cleanUp } }
        .fullScreenCover(item: $model.pendingViewer) { PhotoViewer(context: $0) }
    }
}
