import SwiftUI
import FirebaseCore
import FirebaseAppCheck
import UserNotifications

@main
struct TidyRollApp: App {
    init() {
        // App Check protects every Firebase AI Logic call.
        // Release: Apple App Attest proves a genuine Spectra on a genuine iPhone. The debug provider exists only in Debug builds.
        #if DEBUG
        AppCheck.setAppCheckProviderFactory(AppCheckDebugProviderFactory())
        #else
        AppCheck.setAppCheckProviderFactory(AppAttestProviderFactory())
        #endif
        FirebaseApp.configure()
        _model = State(initialValue: AppModel())   // after Firebase is configured
        UNUserNotificationCenter.current().delegate = DigestTapHandler.shared
    }

    @State private var model: AppModel

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            RootView().environment(model)
                .preferredColorScheme(UITestSupport.scheme)
                .task { await UITestSupport.run(model) }
            #else
            RootView().environment(model)
            #endif
        }
    }
}
