import AppKit
import Combine
import Sparkle
import ClipboardCore

enum UpdateChannel: String, CaseIterable, Identifiable {
    case stable, preview
    var id: String { rawValue }
    var title: String { self == .stable ? L10n.text("Stable releases") : L10n.text("Stable and preview releases") }
    var allowedChannels: Set<String> { self == .preview ? ["preview"] : [] }
}

/// These rules apply even when Sparkle is resuming a previously downloaded update.
struct UpdatePolicy {
    var userInitiated = false
    var activityInProgress = false
    var mayShowUI: Bool { userInitiated && !activityInProgress }
    var mayInstall: Bool { userInitiated && !activityInProgress }

    static func permitsStartup(bundleIdentifier: String?, bundleExtension: String, isTestProcess: Bool) -> Bool {
        bundleIdentifier == "com.smartclipboard.app" && bundleExtension == "app" && !isTestProcess
    }
}

@MainActor protocol UpdateEngine: AnyObject {
    var canCheckForUpdates: Bool { get }
    var sessionInProgress: Bool { get }
    var automaticallyChecksForUpdates: Bool { get set }
    func start() throws
    func checkForUpdates()
    func resetUpdateCycle()
}

@MainActor final class UpdateController: NSObject, ObservableObject {
    static let channelKey = "updateReleaseChannel"
    @Published private(set) var availableVersion: String?
    @Published private(set) var status = L10n.text("Updates have not been checked.")
    @Published private(set) var channel: UpdateChannel = .stable
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var ready = false
    @Published private(set) var activityInProgress = false
    @Published private(set) var sessionInProgress = false
    @Published private(set) var engineCanCheck = false
    private(set) var userInitiated = false
    private(set) var installationRequested = false
    private(set) var installationStaged = false
    private let defaults: UserDefaults
    private let enabled: Bool
    private let isBusy: () -> Bool
    private let makeEngine: @MainActor (UpdateController) -> any UpdateEngine
    private var engine: (any UpdateEngine)?
    private var pendingInstallation: (() -> Void)?

    init(defaults: UserDefaults = .standard, enabled: Bool, isBusy: @escaping () -> Bool,
         makeEngine: @escaping @MainActor (UpdateController) -> any UpdateEngine = { SparkleUpdateEngine(owner: $0) }) {
        self.defaults = defaults
        self.enabled = enabled
        self.isBusy = isBusy
        self.makeEngine = makeEngine
        super.init()
    }

    static func live(isBusy: @escaping () -> Bool) -> UpdateController {
        #if ACCESSIBILITY_AUDIT
        let enabled = false
        #else
        let enabled = UpdatePolicy.permitsStartup(bundleIdentifier: Bundle.main.bundleIdentifier,
                                                  bundleExtension: Bundle.main.bundleURL.pathExtension,
                                                  isTestProcess: NSClassFromString("XCTestCase") != nil ||
                                                    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
        #endif
        return UpdateController(enabled: enabled, isBusy: isBusy)
    }

    /// Initialization never creates Sparkle or accesses preferences. Only normal app launch calls this.
    func start() {
        guard enabled, engine == nil else { return }
        channel = UpdateChannel(rawValue: defaults.string(forKey: Self.channelKey) ?? "") ?? .stable
        let engine = makeEngine(self)
        self.engine = engine
        do {
            try engine.start()
            ready = true
            refreshState()
        } catch {
            status = L10n.text("Updates are unavailable in this build. Download a signed release from the Releases link.")
        }
    }

    var canCheckForUpdates: Bool { ready && engineCanCheck && !activityInProgress && pendingInstallation == nil }
    var canChangePreferences: Bool { ready && !sessionInProgress && !installationRequested }
    var menuTitle: String { availableVersion.map { L10n.text("Update to \($0)…") } ?? L10n.text("Check for Updates…") }
    var policy: UpdatePolicy { UpdatePolicy(userInitiated: userInitiated, activityInProgress: isBusy()) }

    func checkForUpdates() {
        refreshState()
        guard canCheckForUpdates else {
            if activityInProgress { status = L10n.text("Finish the current capture, conversion or file selection before checking for updates.") }
            return
        }
        userInitiated = true
        status = L10n.text("Checking for updates…")
        engine?.checkForUpdates()
        refreshState()
    }

    func setAutomaticallyChecks(_ value: Bool) {
        guard canChangePreferences, let engine else { return }
        // Sparkle owns and persists this preference; do not shadow or reset it at launch.
        engine.automaticallyChecksForUpdates = value
        refreshState()
    }

    func setChannel(_ value: UpdateChannel) {
        guard canChangePreferences, value != channel else { return }
        channel = value
        defaults.set(value.rawValue, forKey: Self.channelKey)
        availableVersion = nil
        status = L10n.text("Release preference changed. Check for updates when ready.")
        engine?.resetUpdateCycle()
    }

    func refreshState() {
        activityInProgress = isBusy()
        engineCanCheck = engine?.canCheckForUpdates ?? false
        sessionInProgress = engine?.sessionInProgress ?? false
        automaticallyChecks = engine?.automaticallyChecksForUpdates ?? false
        if !activityInProgress, let resume = pendingInstallation {
            pendingInstallation = nil
            resume()
        }
    }

    func foundUpdate(version: String, offeredChannel: String? = nil) {
        guard offeredChannel == nil || channel.allowedChannels.contains(offeredChannel!) else {
            availableVersion = nil
            status = L10n.text("That update is outside your selected release preference.")
            return
        }
        availableVersion = version
        status = L10n.text("Version \(version) is available.")
    }

    func suppressedOfferChoice(channel offeredChannel: String?, userInitiated: Bool) -> SPUUserUpdateChoice? {
        // Sparkle can resume a downloaded update without filtering a new appcast.
        // Recheck opt-in here, including updates whose authorization was deferred.
        if let offeredChannel, !channel.allowedChannels.contains(offeredChannel) { return .skip }
        return userInitiated && policy.mayShowUI ? nil : .dismiss
    }

    /// Called only after an explicit Install choice; it also closes the download/capture race.
    func installWhenIdle(_ install: @escaping () -> Void) {
        guard userInitiated else { return }
        installationRequested = true
        if isBusy() {
            status = L10n.text("The update will continue when the current capture, conversion or file selection finishes.")
            pendingInstallation = install
        } else { install() }
    }

    func finishSession() {
        userInitiated = false
        pendingInstallation = nil
        installationRequested = installationStaged
        refreshState()
    }

    func stageInstallation() { installationStaged = true }
    func cancelInstallation() {
        pendingInstallation = nil
        installationRequested = false
        installationStaged = false
    }

    var shouldDelayTermination: Bool { installationRequested && isBusy() }
}

@MainActor private final class SparkleUpdateEngine: UpdateEngine {
    private let updater: SPUUpdater
    private var observations: [NSKeyValueObservation] = []

    init(owner: UpdateController) {
        let driver = QuietUpdateDriver(owner: owner)
        updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: owner)
        observations = [updater.observe(\.canCheckForUpdates, options: [.new]) { [weak owner] _, _ in
            MainActor.assumeIsolated { owner?.refreshState() }
        }, updater.observe(\.sessionInProgress, options: [.new]) { [weak owner] _, _ in
            MainActor.assumeIsolated { owner?.refreshState() }
        }]
    }
    var canCheckForUpdates: Bool { updater.canCheckForUpdates }
    var sessionInProgress: Bool { updater.sessionInProgress }
    var automaticallyChecksForUpdates: Bool {
        get { updater.automaticallyChecksForUpdates }
        set { updater.automaticallyChecksForUpdates = newValue }
    }
    func start() throws { try updater.start() }
    func checkForUpdates() { updater.checkForUpdates() }
    func resetUpdateCycle() { updater.resetUpdateCycleAfterShortDelay() }
}

extension UpdateController: SPUUpdaterDelegate {
    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool { false }
    func allowedSystemProfileKeys(for updater: SPUUpdater) -> [String]? { [] }
    func allowedChannels(for updater: SPUUpdater) -> Set<String> { channel.allowedChannels }
    func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        guard !isBusy() else {
            throw NSError(domain: "SmartClipboard.Update", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: L10n.text("Finish the current capture, conversion or file selection before updating.")])
        }
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        foundUpdate(version: item.displayVersionString, offeredChannel: item.channel)
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        availableVersion = nil
        status = L10n.text("No compatible new update was found for this release preference.")
    }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        if (error as NSError).code != SUError.noUpdateError.rawValue {
            status = L10n.text("The update check could not finish. Try again later or use the Releases link.")
        }
        cancelInstallation()
    }
    func updater(_ updater: SPUUpdater, shouldDownloadReleaseNotesForUpdate updateItem: SUAppcastItem) -> Bool {
        policy.mayShowUI
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem,
                 untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        guard isBusy() else { return false }
        installWhenIdle(installHandler)
        return true
    }
}

/// The stock windows are used only inside a user-requested session. Scheduled offers
/// are dismissed immediately, so they cannot hold a stale preview after opt-out.
@MainActor final class QuietUpdateDriver: NSObject, SPUUserDriver {
    private weak var owner: UpdateController?
    private let standard: any SPUUserDriver
    init(owner: UpdateController, standard: (any SPUUserDriver)? = nil) {
        self.owner = owner
        self.standard = standard ?? SPUStandardUserDriver(hostBundle: .main, delegate: nil)
    }
    private var mayShowUI: Bool { owner?.policy.mayShowUI == true }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        guard mayShowUI else { cancellation(); return }
        standard.showUserInitiatedUpdateCheck(cancellation: cancellation)
    }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let owner else { reply(.dismiss); return }
        if let choice = owner.suppressedOfferChoice(channel: appcastItem.channel, userInitiated: state.userInitiated) {
            reply(choice)
            return
        }
        standard.showUpdateFound(with: appcastItem, state: state) { [weak owner] choice in
            if choice == .install {
                guard let owner else { reply(.dismiss); return }
                owner.installWhenIdle { reply(choice) }
            } else { reply(choice) }
        }
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        if mayShowUI { standard.showUpdateReleaseNotes(with: downloadData) }
    }
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) {
        if mayShowUI { standard.showUpdateReleaseNotesFailedToDownloadWithError(error) }
    }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        guard mayShowUI else { acknowledgement(); return }
        standard.showUpdateNotFoundWithError(error, acknowledgement: acknowledgement)
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        guard mayShowUI else { acknowledgement(); return }
        standard.showUpdaterError(error, acknowledgement: acknowledgement)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        guard mayShowUI else { cancellation(); return }
        standard.showDownloadInitiated(cancellation: cancellation)
    }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        if mayShowUI { standard.showDownloadDidReceiveExpectedContentLength(expectedContentLength) }
    }
    func showDownloadDidReceiveData(ofLength length: UInt64) {
        if mayShowUI { standard.showDownloadDidReceiveData(ofLength: length) }
    }
    func showDownloadDidStartExtractingUpdate() {
        if mayShowUI { standard.showDownloadDidStartExtractingUpdate() }
    }
    func showExtractionReceivedProgress(_ progress: Double) {
        if mayShowUI { standard.showExtractionReceivedProgress(progress) }
    }
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        guard let owner, owner.userInitiated else { reply(.skip); return }
        owner.stageInstallation()
        owner.installWhenIdle { [weak self, weak owner] in
            guard let self else { reply(.skip); return }
            self.standard.showReady(toInstallAndRelaunch: { choice in
                if choice == .install {
                    guard let owner else { reply(.skip); return }
                    owner.installWhenIdle { reply(.install) }
                } else {
                    if choice == .skip { owner?.cancelInstallation() }
                    reply(choice)
                }
            })
        }
    }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        if owner?.userInitiated == true {
            standard.showInstallingUpdate(withApplicationTerminated: applicationTerminated, retryTerminatingApplication: retryTerminatingApplication)
        }
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }
    func dismissUpdateInstallation() {
        standard.dismissUpdateInstallation()
        owner?.finishSession()
    }
    func showUpdateInFocus() {
        if mayShowUI { standard.showUpdateInFocus?() }
    }
}
