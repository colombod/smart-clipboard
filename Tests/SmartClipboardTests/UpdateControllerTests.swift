import AppKit
import Sparkle
import Testing
@testable import SmartClipboard

@MainActor struct UpdateControllerTests {
    private func withController(_ body: (UpdateController, TestUpdateEngine, Activity) throws -> Void) rethrows {
        let name = "UpdateControllerTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let engine = TestUpdateEngine(), activity = Activity()
        let controller = UpdateController(defaults: defaults, enabled: true, isBusy: { activity.busy }, makeEngine: { _ in engine })
        try body(controller, engine, activity)
    }

    @Test func auditAndTestHostsCannotStartProductionUpdater() {
        #expect(!UpdatePolicy.permitsStartup(bundleIdentifier: "com.smartclipboard.accessibility-audit", bundleExtension: "app", isTestProcess: false))
        #expect(!UpdatePolicy.permitsStartup(bundleIdentifier: "com.smartclipboard.app", bundleExtension: "app", isTestProcess: true))
        #expect(!UpdatePolicy.permitsStartup(bundleIdentifier: "com.smartclipboard.app", bundleExtension: "xctest", isTestProcess: false))
        #expect(UpdatePolicy.permitsStartup(bundleIdentifier: "com.smartclipboard.app", bundleExtension: "app", isTestProcess: false))
        var created = false
        let controller = UpdateController(enabled: false, isBusy: { false }, makeEngine: { _ in
            created = true
            return TestUpdateEngine()
        })
        controller.start()
        controller.checkForUpdates()
        #expect(!created)
        #expect(!controller.ready)
    }

    @Test func startupDoesNotCheckOrOverwriteSparklePreferences() {
        withController { controller, engine, _ in
            engine.automaticallyChecksForUpdates = true
            engine.preferenceWrites = 0
            #expect(engine.starts == 0)
            controller.start()
            controller.start()
            #expect(engine.starts == 1)
            #expect(engine.checks == 0)
            #expect(engine.preferenceWrites == 0)
            #expect(controller.automaticallyChecks)
            #expect(!controller.userInitiated)
        }
    }

    @Test func startupFailureIsOnlyAnInlineStatus() {
        withController { controller, engine, _ in
            engine.startFailure = true
            controller.start()
            controller.checkForUpdates()
            #expect(!controller.ready)
            #expect(engine.checks == 0)
            #expect(controller.status.contains("unavailable"))
        }
    }

    @Test func busyCheckIsNotQueuedToOpenALaterWindow() {
        withController { controller, engine, activity in
            controller.start()
            activity.busy = true
            controller.checkForUpdates()
            #expect(engine.checks == 0)
            #expect(!controller.userInitiated)
            activity.busy = false
            controller.refreshState()
            #expect(engine.checks == 0)
            controller.checkForUpdates()
            #expect(engine.checks == 1)
            #expect(controller.userInitiated)
        }
    }

    @Test func installWaitsForCaptureAndOnlyResumesOnce() {
        withController { controller, _, activity in
            controller.start()
            var installations = 0
            controller.installWhenIdle { installations += 1 }
            #expect(installations == 0)
            controller.checkForUpdates()
            activity.busy = true
            controller.installWhenIdle { installations += 1 }
            controller.refreshState()
            #expect(installations == 0)
            #expect(controller.shouldDelayTermination)
            activity.busy = false
            controller.refreshState()
            controller.refreshState()
            #expect(installations == 1)
            #expect(!controller.shouldDelayTermination)
        }
    }

    @Test func cancelledInstallDoesNotResumeWhenCaptureFinishes() {
        withController { controller, _, activity in
            controller.start()
            controller.checkForUpdates()
            activity.busy = true
            var installed = false
            controller.installWhenIdle { installed = true }
            controller.cancelInstallation()
            controller.finishSession()
            activity.busy = false
            controller.refreshState()
            #expect(!installed)
            #expect(!controller.installationRequested)
            #expect(controller.canChangePreferences)
        }
    }

    @Test func importOrSaveSelectionDelaysInstallWithoutTreatingUpdaterWindowsAsBusy() {
        withController { controller, _, activity in
            controller.start()
            controller.checkForUpdates()
            activity.choosingFile = true
            var installations = 0
            controller.installWhenIdle { installations += 1 }
            controller.refreshState()
            #expect(controller.shouldDelayTermination)
            #expect(installations == 0)
            activity.choosingFile = false // The file dialog returned or was cancelled.
            controller.refreshState()
            #expect(installations == 1)
            #expect(controller.policy.mayShowUI)
        }
    }

    @Test func previewRequiresOptInAndOptOutClearsOldOffer() {
        withController { controller, engine, _ in
            controller.start()
            #expect(controller.channel == .stable)
            #expect(controller.channel.allowedChannels.isEmpty)
            controller.setChannel(.preview)
            #expect(controller.channel.allowedChannels == ["preview"])
            controller.foundUpdate(version: "0.5 preview")
            #expect(controller.availableVersion != nil)
            #expect(!controller.userInitiated)
            #expect(engine.checks == 0)
            controller.setChannel(.stable)
            #expect(controller.availableVersion == nil)
            #expect(engine.resets == 2)
            #expect(engine.checks == 0)
        }
    }

    @Test func preferencesCannotChangeDuringExplicitUpdateSession() {
        withController { controller, engine, _ in
            controller.start()
            engine.sessionInProgress = true
            controller.refreshState()
            controller.setChannel(.preview)
            controller.setAutomaticallyChecks(true)
            #expect(controller.channel == .stable)
            #expect(engine.preferenceWrites == 0)
        }
    }

    @Test func previewDownloadedBeforeOptOutCannotResumeAfterAuthorizationWasDeferred() {
        withController { controller, _, _ in
            controller.start()
            controller.setChannel(.preview)
            controller.checkForUpdates()
            #expect(controller.suppressedOfferChoice(channel: "preview", userInitiated: true) == nil)
            controller.finishSession() // Sparkle retained the payload after Authorize Later.
            controller.setChannel(.stable)
            controller.checkForUpdates()
            controller.foundUpdate(version: "0.5 preview", offeredChannel: "preview")
            #expect(controller.suppressedOfferChoice(channel: "preview", userInitiated: true) == .skip)
            #expect(controller.availableVersion == nil)
            #expect(controller.suppressedOfferChoice(channel: "unknown", userInitiated: true) == .skip)
            #expect(controller.suppressedOfferChoice(channel: nil, userInitiated: true) == nil)
        }
    }

    @Test func scheduledOffersAlwaysDismissWithoutDownloadingOrPresenting() {
        withController { controller, engine, activity in
            controller.start()
            #expect(controller.suppressedOfferChoice(channel: nil, userInitiated: false) == .dismiss)
            controller.setChannel(.preview)
            #expect(controller.suppressedOfferChoice(channel: "preview", userInitiated: false) == .dismiss)
            controller.checkForUpdates()
            activity.busy = true
            #expect(controller.suppressedOfferChoice(channel: nil, userInitiated: true) == .dismiss)
            #expect(engine.checks == 1)
        }
    }

    @Test func scheduledErrorsAndProgressNeverOpenStandardUI() {
        withController { controller, _, _ in
            controller.start()
            let ui = RecordingUpdateUI()
            let driver = QuietUpdateDriver(owner: controller, standard: ui)
            var acknowledgements = 0, cancellations = 0
            let error = NSError(domain: "test", code: 1)
            driver.showUpdaterError(error) { acknowledgements += 1 }
            driver.showUpdateNotFoundWithError(error) { acknowledgements += 1 }
            driver.showUserInitiatedUpdateCheck { cancellations += 1 }
            driver.showDownloadInitiated { cancellations += 1 }
            driver.showUpdateInFocus()
            #expect(acknowledgements == 2)
            #expect(cancellations == 2)
            #expect(ui.presentations == 0)
        }
    }

    @Test func explicitUIStopsWhenCaptureStarts() {
        withController { controller, _, activity in
            controller.start()
            controller.checkForUpdates()
            let ui = RecordingUpdateUI()
            let driver = QuietUpdateDriver(owner: controller, standard: ui)
            driver.showUserInitiatedUpdateCheck {}
            #expect(ui.presentations == 1)
            activity.busy = true
            driver.showUpdaterError(NSError(domain: "test", code: 1)) {}
            driver.showUpdateInFocus()
            #expect(ui.presentations == 1)
        }
    }
}

@MainActor private final class Activity {
    private var processing = false
    var choosingFile = false
    var busy: Bool {
        get { processing || choosingFile }
        set { processing = newValue }
    }
}

@MainActor private final class TestUpdateEngine: UpdateEngine {
    var starts = 0, checks = 0, resets = 0, preferenceWrites = 0
    var startFailure = false
    var canCheckForUpdates = true
    var sessionInProgress = false
    var automaticallyChecksForUpdates = false { didSet { preferenceWrites += 1 } }
    func start() throws {
        starts += 1
        if startFailure { throw NSError(domain: "test", code: 1) }
    }
    func checkForUpdates() { checks += 1 }
    func resetUpdateCycle() { resets += 1 }
}

@MainActor private final class RecordingUpdateUI: NSObject, SPUUserDriver {
    var presentations = 0
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) { presentations += 1 }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { presentations += 1 }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) { presentations += 1 }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) { presentations += 1 }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { presentations += 1 }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) { presentations += 1; acknowledgement() }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) { presentations += 1; acknowledgement() }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { presentations += 1 }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { presentations += 1 }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { presentations += 1 }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) { presentations += 1 }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) { acknowledgement() }
    func dismissUpdateInstallation() {}
    func showUpdateInFocus() { presentations += 1 }
}
