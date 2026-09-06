import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(Theme.mint)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor(Theme.background)], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([.foregroundColor: UIColor.label], for: .normal)
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional { DispatchQueue.main.async { application.registerForRemoteNotifications() } }
        }
        return true
    }
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        UserDefaults.standard.set(deviceToken.map { String(format: "%02x", $0) }.joined(), forKey: "pushToken")
        NotificationCenter.default.post(name: .herdrPushRegistered, object: nil)
    }
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .herdrPushFailed, object: error.localizedDescription)
    }
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions { [.banner, .sound, .list] }
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let id = response.notification.request.content.userInfo["agentId"] as? String
        await MainActor.run { NotificationCenter.default.post(name: .herdrOpenAgent, object: id) }
    }
}
extension Notification.Name {
    static let herdrPushRegistered = Notification.Name("herdr.push.registered")
    static let herdrPushFailed = Notification.Name("herdr.push.failed")
    static let herdrOpenAgent = Notification.Name("herdr.open.agent")
}
@main struct HerdrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase
    var body: some Scene {
        WindowGroup {
            Group { if model.hasSession { MainView() } else { PairView() } }
                .environmentObject(model).tint(Theme.mint).preferredColorScheme(.dark)
                .task(id: "\(model.pollIdentity)-\(scenePhase == .active)") {
                    guard scenePhase == .active else { return }
                    await model.updateNotificationPermission()
                    while !Task.isCancelled { await model.refresh(); try? await Task.sleep(for: .seconds(5)) }
                }
                .onOpenURL { model.receivePairLink($0) }
                .onReceive(NotificationCenter.default.publisher(for: .herdrPushRegistered)) { _ in Task { await model.registerSavedPushToken() } }
                .onReceive(NotificationCenter.default.publisher(for: .herdrPushFailed)) { note in model.error = "Push registration failed: \(note.object as? String ?? "Unknown error")" }
                .onReceive(NotificationCenter.default.publisher(for: .herdrOpenAgent)) { note in if let id = note.object as? String { model.openAgent(id) } else { model.selectedTab = 1 } }
                .sheet(isPresented: $model.showPairing) { NavigationStack { PairView().toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { model.showPairing = false } } } }.environmentObject(model) }
        }
    }
}
