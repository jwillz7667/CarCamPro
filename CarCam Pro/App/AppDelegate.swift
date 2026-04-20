import UIKit
import OSLog

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        AppLogger.ui.info("Application did finish launching")
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        AppLogger.ui.info("Application did enter background")
    }

    func applicationWillTerminate(_ application: UIApplication) {
        AppLogger.ui.info("Application will terminate")
    }

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        AppLogger.ui.warning("Application received memory warning")
    }
}
