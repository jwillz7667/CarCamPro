import SwiftUI
import SwiftData

@main
struct CarCam_ProApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var container = DependencyContainer()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            RecordingSession.self,
            VideoClip.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(container)
                .preferredColorScheme(.dark)
                .tint(CCTheme.amber)
                .onAppear {
                    container.configure(modelContainer: sharedModelContainer)
                }
        }
        .modelContainer(sharedModelContainer)
    }
}
