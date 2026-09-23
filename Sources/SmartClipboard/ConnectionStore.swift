import Foundation
import Combine
import ClipboardCore

/// Stores connection choices only. Secrets are read from Keychain by explicit actions.
@MainActor final class ConnectionStore: ObservableObject {
    static let settingsKey = "connectionSettings"
    private static let currentVersion = 1

    private struct Settings: Codable {
        var version: Int
        var activeProvider: AIProvider
        var profiles: [ConnectionProfile]
    }

    @Published var activeProvider: AIProvider {
        didSet {
            guard activeProvider != oldValue else { return }
            invalidate()
            persist()
        }
    }
    @Published private(set) var profiles: [ConnectionProfile]
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var testSuccess: String?
    @Published private(set) var configurationWarning: String?
    private let defaults: UserDefaults

    var activeProfile: ConnectionProfile { profile(for: activeProvider) }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if defaults.object(forKey: Self.settingsKey) != nil {
            if let data = defaults.data(forKey: Self.settingsKey),
               let saved = try? JSONDecoder().decode(Settings.self, from: data),
               Self.isValid(saved) {
                activeProvider = saved.activeProvider
                profiles = saved.profiles
            } else {
                // Placeholders are only for repairing Settings; validatedProfile blocks their use.
                activeProvider = .openai
                profiles = AIProvider.allCases.map { ConnectionProfile(provider: $0) }
                configurationWarning = L10n.text("Saved connection settings could not be read. AI processing is paused. Select a provider and edit its connection to replace the unreadable settings.")
            }
        } else {
            activeProvider = defaults.string(forKey: "provider") == "codex" ? .codex : .openai
            profiles = Self.legacyProfiles(defaults: defaults)
            persist()
        }
    }

    func validatedProfile() throws -> ConnectionProfile {
        if let configurationWarning { throw ClipError.message(configurationWarning) }
        guard let profile = profiles.first(where: { $0.provider == activeProvider && $0.id == activeProvider.rawValue }) else {
            throw ClipError.message(L10n.text("Choose a valid AI connection in Settings → Connection before processing images."))
        }
        return profile
    }

    func profile(for provider: AIProvider) -> ConnectionProfile {
        profiles.first(where: { $0.provider == provider }) ?? ConnectionProfile(provider: provider)
    }

    func update(_ profile: ConnectionProfile) {
        guard let position = profiles.firstIndex(where: { $0.provider == profile.provider }) else { return }
        var updated = profile
        // One saved profile per route gives each credential a stable Keychain account.
        updated.id = profile.provider.rawValue
        guard profiles[position] != updated else { return }
        profiles[position] = updated
        invalidate()
        persist()
    }

    func credentialsDidChange(for profile: ConnectionProfile) {
        guard profiles.contains(where: { $0.credentialAccount == profile.credentialAccount }) else { return }
        invalidate()
    }

    @discardableResult
    func recordTestSuccess(_ message: String, for profile: ConnectionProfile, revision testedRevision: UInt64) -> Bool {
        guard configurationWarning == nil, revision == testedRevision, activeProfile == profile else { return false }
        testSuccess = message
        return true
    }

    func clearTestSuccess() { testSuccess = nil }

    private func invalidate() {
        revision &+= 1
        testSuccess = nil
    }

    private func persist() {
        let settings = Settings(version: Self.currentVersion, activeProvider: activeProvider, profiles: profiles)
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.settingsKey)
            configurationWarning = nil
        } catch {
            configurationWarning = L10n.text("Could not save connection settings: \(error.localizedDescription)")
        }
    }

    private static func legacyProfiles(defaults: UserDefaults) -> [ConnectionProfile] {
        AIProvider.allCases.map { provider in
            switch provider {
            case .openai:
                return ConnectionProfile(provider: provider, model: defaults.string(forKey: "apiModel") ?? "gpt-5.6-luna")
            case .codex:
                return ConnectionProfile(provider: provider, model: defaults.string(forKey: "codexModel") ?? "", executable: defaults.string(forKey: "codexExecutable") ?? "")
            default:
                return ConnectionProfile(provider: provider)
            }
        }
    }

    private static func isValid(_ settings: Settings) -> Bool {
        let providers = Set(AIProvider.allCases)
        return settings.version == currentVersion
            && settings.profiles.count == providers.count
            && Set(settings.profiles.map(\.provider)) == providers
            && settings.profiles.allSatisfy { $0.id == $0.provider.rawValue }
            && settings.profiles.contains { $0.provider == settings.activeProvider }
    }
}
