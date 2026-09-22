import Foundation
import Testing
import ClipboardCore
@testable import SmartClipboard

@MainActor struct ConnectionStoreTests {
    private func withDefaults(_ test: (UserDefaults) throws -> Void) rethrows {
        let name = "ConnectionStoreTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try test(defaults)
    }

    @Test func migratesBothLegacyRoutesAndKeepsTheExistingKeychainAccount() throws {
        try withDefaults { defaults in
            defaults.set("codex", forKey: "provider")
            defaults.set("existing-api-model", forKey: "apiModel")
            defaults.set("existing-codex-model", forKey: "codexModel")
            defaults.set("/custom/bin/codex", forKey: "codexExecutable")
            let store = ConnectionStore(defaults: defaults)
            #expect(store.activeProvider == .codex)
            #expect(try store.validatedProfile().provider == .codex)
            #expect(store.activeProfile.model == "existing-codex-model")
            #expect(store.activeProfile.executable == "/custom/bin/codex")
            #expect(store.profile(for: .openai).model == "existing-api-model")
            #expect(store.profile(for: .openai).credentialAccount == "openai-api-key")
            #expect(store.profiles.count == AIProvider.allCases.count)
            #expect(Set(store.profiles.map(\.credentialAccount)).count == store.profiles.count)
            let data = try #require(defaults.data(forKey: ConnectionStore.settingsKey))
            let saved = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(saved["version"] as? Int == 1)
        }
    }

    @Test func newPreferencesKeepEachRoutesModelAndEndpointAcrossRestarts() {
        withDefaults { defaults in
            let store = ConnectionStore(defaults: defaults)
            store.activeProvider = .omlx
            var local = store.activeProfile
            local.model = "local-vision"
            local.endpoint = "http://192.168.1.10:8000/v1"
            store.update(local)
            store.activeProvider = .anthropic
            var anthropic = store.activeProfile
            anthropic.model = "selected-vision"
            store.update(anthropic)
            defaults.set("codex", forKey: "provider")
            defaults.set("changed-legacy-value", forKey: "apiModel")
            let reopened = ConnectionStore(defaults: defaults)
            #expect(reopened.activeProvider == .anthropic)
            #expect(reopened.activeProfile == anthropic)
            #expect(reopened.profile(for: .omlx) == local)
            #expect(reopened.profile(for: .openai).model != "changed-legacy-value")
            #expect(reopened.testSuccess == nil)
        }
    }

    @Test func settingsChangesInvalidateSuccessAndRejectLateResults() {
        withDefaults { defaults in
            let store = ConnectionStore(defaults: defaults)
            let original = store.activeProfile, revision = store.revision
            #expect(store.recordTestSuccess("Image test passed", for: original, revision: revision))
            store.update(original)
            #expect(store.testSuccess == "Image test passed")
            #expect(store.revision == revision)
            var updated = original
            updated.model = "another-model"
            store.update(updated)
            #expect(store.testSuccess == nil)
            #expect(!store.recordTestSuccess("Stale success", for: original, revision: revision))
            store.update(original)
            #expect(!store.recordTestSuccess("Still stale", for: original, revision: revision))
            #expect(store.recordTestSuccess("Current success", for: original, revision: store.revision))
            store.activeProvider = .google
            #expect(store.testSuccess == nil)
            #expect(!store.recordTestSuccess("Wrong route", for: original, revision: store.revision))
        }
    }

    @Test func credentialChangesInvalidateSuccessWithoutSavingSecrets() throws {
        try withDefaults { defaults in
            let store = ConnectionStore(defaults: defaults)
            let profile = store.activeProfile, revision = store.revision
            let before = try #require(defaults.data(forKey: ConnectionStore.settingsKey))
            #expect(store.recordTestSuccess("Passed", for: profile, revision: revision))
            store.credentialsDidChange(for: profile)
            #expect(store.testSuccess == nil)
            #expect(store.revision > revision)
            #expect(!store.recordTestSuccess("Stale credentials", for: profile, revision: revision))
            #expect(defaults.data(forKey: ConnectionStore.settingsKey) == before)
        }
    }

    @Test func endpointAndExecutableChangesInvalidateVerification() {
        withDefaults { defaults in
            let store = ConnectionStore(defaults: defaults)
            for provider in [AIProvider.omlx, .codex] {
                store.activeProvider = provider
                var profile = store.activeProfile
                #expect(store.recordTestSuccess("Passed", for: profile, revision: store.revision))
                if provider == .omlx { profile.endpoint = "http://localhost:9000/v1" }
                else { profile.executable = "/another/codex" }
                store.update(profile)
                #expect(store.testSuccess == nil)
            }
        }
    }

    @Test func unreadableOrFutureSettingsArePreservedUntilAnExplicitEdit() {
        withDefaults { defaults in
            for bytes in [Data("corrupt".utf8), Data("{\"version\":99,\"activeProvider\":\"openai\",\"profiles\":[]}".utf8)] {
                defaults.set(bytes, forKey: ConnectionStore.settingsKey)
                let store = ConnectionStore(defaults: defaults)
                #expect(store.configurationWarning != nil)
                #expect(throws: ClipError.self) { try store.validatedProfile() }
                #expect(!store.recordTestSuccess("Cannot verify placeholders", for: store.activeProfile, revision: store.revision))
                #expect(defaults.data(forKey: ConnectionStore.settingsKey) == bytes)
                var profile = store.activeProfile
                profile.model = "explicit-choice"
                store.update(profile)
                #expect(store.configurationWarning == nil)
                #expect((try? store.validatedProfile()) == profile)
                #expect(defaults.data(forKey: ConnectionStore.settingsKey) != bytes)
            }
        }
    }

    @Test func malformedSavedProfilesNeverRouteLocalCapturesToLegacyCloudSettings() throws {
        try withDefaults { defaults in
            let original = ConnectionStore(defaults: defaults)
            original.activeProvider = .omlx
            var local = original.activeProfile
            local.model = "local-vision"
            local.endpoint = "http://192.168.1.20:8000/v1"
            original.update(local)
            let data = try #require(defaults.data(forKey: ConnectionStore.settingsKey))
            let base = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let rows = try #require(base["profiles"] as? [[String: Any]])
            let localIndex = try #require(rows.firstIndex { $0["provider"] as? String == "omlx" })

            var missing = rows
            missing.remove(at: localIndex)
            var duplicate = rows
            duplicate[localIndex] = rows[0]
            var badIdentity = rows
            badIdentity[localIndex]["id"] = "wrong-account"
            var missingEndpoint = rows
            missingEndpoint[localIndex].removeValue(forKey: "endpoint")
            var malformedModel = rows
            malformedModel[localIndex]["model"] = 123

            defaults.set("api", forKey: "provider")
            defaults.set("legacy-cloud-model", forKey: "apiModel")
            for brokenRows in [missing, duplicate, badIdentity, missingEndpoint, malformedModel] {
                var malformed = base
                malformed["profiles"] = brokenRows
                let bytes = try JSONSerialization.data(withJSONObject: malformed)
                defaults.set(bytes, forKey: ConnectionStore.settingsKey)
                let store = ConnectionStore(defaults: defaults)
                #expect(throws: ClipError.self) { try store.validatedProfile() }
                #expect(store.configurationWarning != nil)
                #expect(defaults.data(forKey: ConnectionStore.settingsKey) == bytes)
                #expect(store.profile(for: .openai).model != "legacy-cloud-model")
            }

            var unknownSelection = base
            unknownSelection["activeProvider"] = "unknown-provider"
            let bytes = try JSONSerialization.data(withJSONObject: unknownSelection)
            defaults.set(bytes, forKey: ConnectionStore.settingsKey)
            #expect(throws: ClipError.self) { try ConnectionStore(defaults: defaults).validatedProfile() }
            #expect(defaults.data(forKey: ConnectionStore.settingsKey) == bytes)
        }
    }

    @Test func anExistingNonDataValueCannotTriggerLegacyMigration() {
        withDefaults { defaults in
            defaults.set("not configuration data", forKey: ConnectionStore.settingsKey)
            defaults.set("codex", forKey: "provider")
            let store = ConnectionStore(defaults: defaults)
            #expect(store.configurationWarning != nil)
            #expect(throws: ClipError.self) { try store.validatedProfile() }
            #expect(defaults.string(forKey: ConnectionStore.settingsKey) == "not configuration data")
        }
    }
}
