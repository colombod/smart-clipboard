import Foundation
import ClipboardCore
import Testing
@testable import SmartClipboard

@MainActor struct CaptureNotificationsTests {
    @Test func initializationAndCaptureNeverAskForPermission() async {
        let backend = RecordingNotificationBackend()
        let service = CaptureNotifications(defaults: NotificationTestDefaults(), backend: backend)
        #expect(!service.enabled)
        #expect(service.notifyOnSuccess && service.notifyOnFailure)
        #expect(!service.playsSound)
        #expect(backend.settingsReads == 0 && backend.permissionRequests == 0)
        #expect(service.notifyCopied(format: .text) == nil)
        #expect(service.notifyFailed() == nil)
        await service.refreshAuthorization()
        #expect(service.authorization == .notDetermined)
        #expect(backend.settingsReads == 1 && backend.permissionRequests == 0)
        #expect(backend.posted.isEmpty)
    }

    @Test func explicitEnablePersistsChoiceAndOnlyPostsPredefinedMetadata() async {
        let defaults = NotificationTestDefaults(), backend = RecordingNotificationBackend()
        backend.current = .allowed
        let service = CaptureNotifications(defaults: defaults, backend: backend)
        await service.enableFromSettings()
        #expect(service.enabled)
        #expect(backend.permissionRequests == 1)
        await service.notifyCopied(format: .markdown)?.value
        await service.notifyFailed()?.value
        #expect(backend.posted == [.copied(.markdown, sound: false), .failed(sound: false)])
        #expect(backend.posted[0].title == "Ready to paste")
        #expect(backend.posted[0].body == "Markdown is on the clipboard. Paste with ⌘V.")
        #expect(backend.posted[1].body == "Open Smart Clipboard to check the status and try again.")
        #expect(backend.permissionRequests == 1)
        let relaunched = CaptureNotifications(defaults: defaults, backend: backend)
        #expect(relaunched.enabled)
        #expect(backend.permissionRequests == 1)
    }

    @Test func deniedPermissionStaysOffAndSettingsLinkIsExplicit() async {
        let backend = RecordingNotificationBackend()
        backend.current = .init(authorization: .denied, alertsEnabled: false, soundEnabled: false)
        backend.granted = false
        let service = CaptureNotifications(defaults: NotificationTestDefaults(), backend: backend)
        await service.enableFromSettings()
        #expect(!service.enabled)
        #expect(service.status.contains("blocked"))
        #expect(service.notifyFailed() == nil)
        #expect(backend.settingsOpens == 0)
        service.openSystemSettings()
        #expect(backend.settingsOpens == 1)
        #expect(backend.permissionRequests == 1)
    }

    @Test func successFailureAndSoundPreferencesAreIndependent() async {
        let defaults = NotificationTestDefaults(), backend = RecordingNotificationBackend()
        backend.current = .allowed
        let service = CaptureNotifications(defaults: defaults, backend: backend)
        await service.enableFromSettings()
        service.notifyOnSuccess = false
        service.playsSound = true
        #expect(service.notifyCopied(format: .image) == nil)
        await service.notifyFailed()?.value
        #expect(backend.posted == [.failed(sound: true)])
        service.notifyOnFailure = false
        service.notifyOnSuccess = true
        #expect(service.notifyFailed() == nil)
        backend.current.soundEnabled = false
        await service.notifyCopied(format: .image)?.value
        #expect(backend.posted.last == .copied(.image, sound: false))
        let restored = CaptureNotifications(defaults: defaults, backend: backend)
        #expect(restored.playsSound && restored.notifyOnSuccess && !restored.notifyOnFailure)
    }

    @Test func externalPermissionRevocationIsReadWithoutPrompting() async {
        let backend = RecordingNotificationBackend()
        backend.current = .allowed
        let service = CaptureNotifications(defaults: NotificationTestDefaults(), backend: backend)
        await service.enableFromSettings()
        backend.current = .init(authorization: .denied, alertsEnabled: false, soundEnabled: false)
        await service.notifyCopied(format: .text)?.value
        #expect(backend.posted.isEmpty)
        #expect(service.authorization == .denied)
        #expect(backend.permissionRequests == 1)
        backend.current = .init(authorization: .authorized, alertsEnabled: false, soundEnabled: false)
        await service.refreshAuthorization()
        #expect(service.status.contains("banners are off"))
    }

    @Test func turningOffWhileSettingsReadIsPendingSuppressesDelivery() async throws {
        let backend = RecordingNotificationBackend()
        backend.current = .allowed
        let service = CaptureNotifications(defaults: NotificationTestDefaults(), backend: backend)
        await service.enableFromSettings()
        backend.deferSettings = true
        let task = try #require(service.notifyCopied(format: .json))
        for _ in 0..<100 where backend.pendingSettings == nil { await Task.yield() }
        let pending = try #require(backend.pendingSettings)
        service.disable()
        pending.resume(returning: .allowed)
        await task.value
        #expect(backend.posted.isEmpty)
        #expect(!service.enabled)
    }

    @Test func staleQuietReadCannotReplaceNewlyGrantedPermission() async throws {
        let backend = RecordingNotificationBackend()
        let service = CaptureNotifications(defaults: NotificationTestDefaults(), backend: backend)
        backend.deferSettings = true
        let refresh = Task { await service.refreshAuthorization() }
        for _ in 0..<100 where backend.pendingSettings == nil { await Task.yield() }
        let pending = try #require(backend.pendingSettings)
        backend.deferSettings = false
        backend.current = .allowed
        await service.enableFromSettings()
        pending.resume(returning: .init(authorization: .notDetermined, alertsEnabled: false, soundEnabled: false))
        await refresh.value
        #expect(service.enabled)
        #expect(service.authorization == .authorized)
        #expect(service.alertsEnabled && service.soundEnabled)
        #expect(backend.permissionRequests == 1)
    }

    @Test func cancellingPendingDeliveryDoesNotPost() async throws {
        let backend = RecordingNotificationBackend()
        backend.current = .allowed
        let service = CaptureNotifications(defaults: NotificationTestDefaults(), backend: backend)
        await service.enableFromSettings()
        backend.deferSettings = true
        let task = try #require(service.notifyFailed())
        for _ in 0..<100 where backend.pendingSettings == nil { await Task.yield() }
        let pending = try #require(backend.pendingSettings)
        task.cancel()
        pending.resume(returning: .allowed)
        await task.value
        #expect(backend.posted.isEmpty)
    }

    @Test func backendErrorsAreGenericAndDoNotOpenAnything() async {
        let backend = RecordingNotificationBackend()
        backend.current = .allowed
        backend.failPermission = true
        let service = CaptureNotifications(defaults: NotificationTestDefaults(), backend: backend)
        await service.enableFromSettings()
        #expect(!service.enabled)
        #expect(service.message?.contains("private detail") == false)
        backend.failPermission = false
        await service.enableFromSettings()
        backend.failPost = true
        await service.notifyFailed()?.value
        #expect(service.message?.contains("could not deliver") == true)
        #expect(service.message?.contains("private detail") == false)
        #expect(backend.settingsOpens == 0)
    }

    @Test func testsAndAuditBuildsCannotCreateLiveBackend() async {
        #expect(!CaptureNotifications.permitsLiveBackend(bundleIdentifier: "com.smartclipboard.accessibility-audit", bundleExtension: "app", isTestProcess: false))
        #expect(!CaptureNotifications.permitsLiveBackend(bundleIdentifier: "com.smartclipboard.app", bundleExtension: "app", isTestProcess: true))
        #expect(!CaptureNotifications.permitsLiveBackend(bundleIdentifier: "com.smartclipboard.app", bundleExtension: "xctest", isTestProcess: false))
        #expect(CaptureNotifications.permitsLiveBackend(bundleIdentifier: "com.smartclipboard.app", bundleExtension: "app", isTestProcess: false))
        let defaults = NotificationTestDefaults()
        let service = CaptureNotifications.disabled(defaults: defaults)
        await service.enableFromSettings()
        await service.refreshAuthorization()
        service.openSystemSettings()
        #expect(service.notifyCopied(format: .text) == nil)
        #expect(service.notifyFailed() == nil)
        #expect(!service.isAvailable && !service.enabled)
        #expect(defaults.writes == 0)
    }
}

private extension CaptureNotificationSettings {
    static var allowed: Self { .init(authorization: .authorized, alertsEnabled: true, soundEnabled: true) }
}

@MainActor private final class RecordingNotificationBackend: CaptureNotificationBackend {
    var current = CaptureNotificationSettings(authorization: .notDetermined, alertsEnabled: false, soundEnabled: false)
    var settingsReads = 0, permissionRequests = 0, settingsOpens = 0
    var granted = true, failPermission = false, failPost = false, deferSettings = false
    var pendingSettings: CheckedContinuation<CaptureNotificationSettings, Never>?
    var posted: [CaptureNotificationMessage] = []
    func settings() async -> CaptureNotificationSettings {
        settingsReads += 1
        if deferSettings { return await withCheckedContinuation { pendingSettings = $0 } }
        return current
    }
    func requestAuthorization() async throws -> Bool {
        permissionRequests += 1
        if failPermission { throw NSError(domain: "private detail", code: 1) }
        return granted
    }
    func post(_ message: CaptureNotificationMessage) async throws {
        if failPost { throw NSError(domain: "private detail", code: 2) }
        posted.append(message)
    }
    func openSystemSettings() -> Bool { settingsOpens += 1; return true }
}

private final class NotificationTestDefaults: UserDefaults, @unchecked Sendable {
    private var values: [String: Any] = [:]
    private(set) var writes = 0
    override func object(forKey defaultName: String) -> Any? { values[defaultName] }
    override func bool(forKey defaultName: String) -> Bool { values[defaultName] as? Bool ?? false }
    override func set(_ value: Any?, forKey defaultName: String) { values[defaultName] = value; writes += 1 }
}
