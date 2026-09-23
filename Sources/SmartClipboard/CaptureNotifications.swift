import AppKit
import Combine
import ClipboardCore
import UserNotifications

enum CaptureNotificationAuthorization: Equatable {
    case unknown, notDetermined, denied, authorized, provisional
    var permitsDelivery: Bool { self == .authorized || self == .provisional }
}

struct CaptureNotificationSettings: Equatable {
    var authorization: CaptureNotificationAuthorization
    var alertsEnabled: Bool
    var soundEnabled: Bool
}

/// The interface cannot accept screenshot text, file names or provider errors.
enum CaptureNotificationMessage: Equatable {
    case copied(OutputFormat, sound: Bool)
    case failed(sound: Bool)

    var title: String {
        switch self {
        case .copied: return L10n.text("Ready to paste")
        case .failed: return L10n.text("Capture couldn't finish")
        }
    }
    var body: String {
        switch self {
        case .copied(let format, _): return L10n.text("\(format.title) is on the clipboard. Paste with ⌘V.")
        case .failed: return L10n.text("Open Smart Clipboard to check the status and try again.")
        }
    }
    var sound: Bool {
        switch self {
        case .copied(_, let sound), .failed(let sound): return sound
        }
    }
}

@MainActor protocol CaptureNotificationBackend: AnyObject {
    func settings() async -> CaptureNotificationSettings
    func requestAuthorization() async throws -> Bool
    func post(_ message: CaptureNotificationMessage) async throws
    func openSystemSettings() -> Bool
}

@MainActor final class CaptureNotifications: ObservableObject {
    private enum Key {
        static let enabled = "captureNotificationsEnabled"
        static let success = "captureNotificationsOnSuccess"
        static let failure = "captureNotificationsOnFailure"
        static let sound = "captureNotificationsSound"
    }

    @Published private(set) var enabled: Bool
    @Published var notifyOnSuccess: Bool { didSet { save(notifyOnSuccess, key: Key.success) } }
    @Published var notifyOnFailure: Bool { didSet { save(notifyOnFailure, key: Key.failure) } }
    @Published var playsSound: Bool { didSet { save(playsSound, key: Key.sound) } }
    @Published private(set) var authorization = CaptureNotificationAuthorization.unknown
    @Published private(set) var alertsEnabled = false
    @Published private(set) var soundEnabled = false
    @Published private(set) var requestingPermission = false
    @Published private(set) var message: String?
    private let defaults: UserDefaults
    private let backend: (any CaptureNotificationBackend)?
    private var preferenceRevision = 0
    private var settingsRevision = 0

    init(defaults: UserDefaults = .standard, backend: (any CaptureNotificationBackend)?) {
        self.defaults = defaults
        self.backend = backend
        enabled = backend != nil && defaults.bool(forKey: Key.enabled)
        notifyOnSuccess = defaults.object(forKey: Key.success) as? Bool ?? true
        notifyOnFailure = defaults.object(forKey: Key.failure) as? Bool ?? true
        playsSound = defaults.bool(forKey: Key.sound)
    }

    static func disabled(defaults: UserDefaults = .standard) -> CaptureNotifications {
        CaptureNotifications(defaults: defaults, backend: nil)
    }

    /// Called only by the normal app lifecycle, never by an AppModel initializer.
    static func live(defaults: UserDefaults = .standard, onOpen: @escaping () -> Void) -> CaptureNotifications {
        #if ACCESSIBILITY_AUDIT
        return disabled(defaults: defaults)
        #else
        guard permitsLiveBackend(bundleIdentifier: Bundle.main.bundleIdentifier,
                                 bundleExtension: Bundle.main.bundleURL.pathExtension,
                                 isTestProcess: NSClassFromString("XCTestCase") != nil ||
                                    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil) else {
            return disabled(defaults: defaults)
        }
        return CaptureNotifications(defaults: defaults, backend: SystemCaptureNotificationBackend(onOpen: onOpen))
        #endif
    }

    static func permitsLiveBackend(bundleIdentifier: String?, bundleExtension: String, isTestProcess: Bool) -> Bool {
        bundleIdentifier == "com.smartclipboard.app" && bundleExtension == "app" && !isTestProcess
    }

    var isAvailable: Bool { backend != nil }
    var status: String {
        guard isAvailable else { return L10n.text("Notifications are unavailable in this test or audit build.") }
        switch authorization {
        case .unknown: return L10n.text("Notification permission has not been checked.")
        case .notDetermined: return L10n.text("Choose Enable notifications to ask macOS for permission.")
        case .denied: return L10n.text("Notifications are blocked in macOS. Allow them in System Settings.")
        case .provisional: return L10n.text("macOS allows quiet notifications. Enable banners in System Settings if desired.")
        case .authorized:
            if !alertsEnabled { return L10n.text("macOS banners are off. Check notification settings to show alerts.") }
            return enabled ? L10n.text("Notifications are enabled for Smart Clipboard.") : L10n.text("macOS permission is granted. Notifications are off in this app.")
        }
    }

    /// The only path that asks macOS for permission; captures and launch only read settings.
    func enableFromSettings() async {
        guard let backend, !requestingPermission else { return }
        requestingPermission = true
        message = nil
        let revision = preferenceRevision
        defer { requestingPermission = false }
        do {
            _ = try await backend.requestAuthorization()
            let settings = await readSettings(from: backend)
            guard revision == preferenceRevision else { return }
            enabled = settings.authorization.permitsDelivery
            defaults.set(enabled, forKey: Key.enabled)
        } catch {
            guard revision == preferenceRevision else { return }
            message = L10n.text("macOS could not enable notifications. Check System Settings and try again.")
        }
    }

    func disable() {
        guard isAvailable else { return }
        preferenceRevision += 1
        enabled = false
        defaults.set(false, forKey: Key.enabled)
        message = nil
    }

    func refreshAuthorization() async {
        guard let backend else { return }
        _ = await readSettings(from: backend)
    }

    func openSystemSettings() {
        guard let backend else { return }
        if !backend.openSystemSettings() {
            message = L10n.text("Open System Settings → Notifications → Smart Clipboard.")
        }
    }

    @discardableResult func notifyCopied(format: OutputFormat) -> Task<Void, Never>? {
        deliver(success: true, format: format)
    }

    @discardableResult func notifyFailed() -> Task<Void, Never>? {
        deliver(success: false, format: nil)
    }

    private func deliver(success: Bool, format: OutputFormat?) -> Task<Void, Never>? {
        guard let backend, enabled, success ? notifyOnSuccess : notifyOnFailure else { return nil }
        let revision = preferenceRevision
        return Task { [weak self] in
            guard let self else { return }
            let settings = await self.readSettings(from: backend)
            guard !Task.isCancelled, self.enabled, revision == self.preferenceRevision,
                  settings.authorization.permitsDelivery,
                  success ? self.notifyOnSuccess : self.notifyOnFailure else { return }
            let sound = self.playsSound && settings.soundEnabled
            let content: CaptureNotificationMessage = success
                ? .copied(format ?? .text, sound: sound) : .failed(sound: sound)
            do {
                try await backend.post(content)
                self.message = nil
            }
            catch { self.message = L10n.text("macOS could not deliver a notification. The capture status remains available in the Clip menu.") }
        }
    }

    private func save(_ value: Bool, key: String) {
        guard isAvailable else { return }
        preferenceRevision += 1
        defaults.set(value, forKey: key)
    }

    private func readSettings(from backend: any CaptureNotificationBackend) async -> CaptureNotificationSettings {
        settingsRevision += 1
        let revision = settingsRevision
        let settings = await backend.settings()
        // A read started before an explicit permission change must not replace newer UI state.
        if revision == settingsRevision {
            authorization = settings.authorization
            alertsEnabled = settings.alertsEnabled
            soundEnabled = settings.soundEnabled
        }
        return settings
    }
}

@MainActor private final class SystemCaptureNotificationBackend: NSObject, CaptureNotificationBackend, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private let onOpen: () -> Void
    private static let identifierPrefix = "capture-status."

    init(onOpen: @escaping () -> Void) {
        self.onOpen = onOpen
        center = UNUserNotificationCenter.current()
        super.init()
        center.delegate = self
    }

    func settings() async -> CaptureNotificationSettings {
        let settings = await center.notificationSettings()
        let authorization: CaptureNotificationAuthorization
        switch settings.authorizationStatus {
        case .notDetermined: authorization = .notDetermined
        case .denied: authorization = .denied
        case .authorized: authorization = .authorized
        case .provisional: authorization = .provisional
        @unknown default: authorization = .unknown
        }
        return CaptureNotificationSettings(authorization: authorization,
                                           alertsEnabled: settings.alertSetting == .enabled,
                                           soundEnabled: settings.soundSetting == .enabled)
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound])
    }

    func post(_ message: CaptureNotificationMessage) async throws {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        if message.sound { content.sound = .default }
        let request = UNNotificationRequest(identifier: Self.identifierPrefix + UUID().uuidString,
                                            content: content, trigger: nil)
        try await center.add(request)
    }

    func openSystemSettings() -> Bool {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                           withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        guard notification.request.identifier.hasPrefix("capture-status.") else { completionHandler([]); return }
        var options: UNNotificationPresentationOptions = [.banner, .list]
        if notification.request.content.sound != nil { options.insert(.sound) }
        completionHandler(options)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                           withCompletionHandler completionHandler: @escaping () -> Void) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              response.notification.request.identifier.hasPrefix("capture-status.") else {
            completionHandler()
            return
        }
        Task { @MainActor [weak self] in
            self?.onOpen()
            completionHandler()
        }
    }
}
