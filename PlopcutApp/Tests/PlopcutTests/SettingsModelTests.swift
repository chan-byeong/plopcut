import Foundation
import PlopcutCore
import SwiftUI
import Testing
@testable import Plopcut

@MainActor
@Suite struct SettingsModelTests {
    private func makeStore() -> (SettingsStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("settings-model-\(UUID().uuidString)")
        let file = dir.appendingPathComponent("settings.json")
        return (SettingsStore(fileURL: file), file)
    }

    @Test func startsFromStoredValues() throws {
        let (store, _) = makeStore()
        _ = try store.update(SettingsUpdate(theme: .dark, captureConfirmationMode: .instant))
        let model = SettingsModel(store: store, appVersion: "1.2.3")
        #expect(model.theme == .dark)
        #expect(model.captureMode == .instant)
        #expect(model.appVersion == "1.2.3")
    }

    @Test func defaultsWhenNothingIsStored() {
        let (store, _) = makeStore()
        let model = SettingsModel(store: store, appVersion: "1")
        #expect(model.theme == .system)
        #expect(model.captureMode == .modal)
    }

    @Test func changingThemePersistsAndKeepsOtherFields() throws {
        let (store, _) = makeStore()
        _ = try store.update(SettingsUpdate(selectedTextShortcut: "Shift+Cmd+K", recentTags: ["a"]))
        let model = SettingsModel(store: store, appVersion: "1")
        model.setTheme(.light)
        let stored = try store.read()
        #expect(model.theme == .light)
        #expect(stored.theme == .light)
        #expect(stored.selectedTextShortcut == "Shift+Cmd+K")
        #expect(stored.recentTags == ["a"])
        #expect(stored.captureConfirmationMode == .modal)
    }

    @Test func changingCaptureModePersistsAndKeepsTheme() throws {
        let (store, _) = makeStore()
        let model = SettingsModel(store: store, appVersion: "1")
        model.setTheme(.dark)
        model.setCaptureMode(.instant)
        let stored = try store.read()
        #expect(stored.captureConfirmationMode == .instant)
        #expect(stored.theme == .dark)
    }

    @Test func failedWriteRollsTheChoiceBackAndExplains() throws {
        let (store, file) = makeStore()
        let model = SettingsModel(store: store, appVersion: "1")
        // A directory where the file should be makes the atomic write fail.
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: true)
        model.setTheme(.dark)
        #expect(model.theme == .system)
        #expect(model.errorMessage != nil)
    }

    @Test func colorSchemeFollowsTheme() {
        let (store, _) = makeStore()
        let model = SettingsModel(store: store, appVersion: "1", devOverride: nil)
        #expect(model.colorScheme == nil)
        model.setTheme(.light)
        #expect(model.colorScheme == .light)
        model.setTheme(.dark)
        #expect(model.colorScheme == .dark)
        model.setTheme(.system)
        #expect(model.colorScheme == nil)
    }

    @Test func devOverrideOnlyAppliesWhileThemeIsSystem() {
        let (store, _) = makeStore()
        let model = SettingsModel(store: store, appVersion: "1", devOverride: .dark)
        #expect(model.colorScheme == .dark)
        model.setTheme(.light)
        #expect(model.colorScheme == .light)
    }

    @Test func versionFallsBackWhenBundleHasNone() {
        #expect(SettingsModel.bundleVersion(from: [:]) == "dev")
        #expect(SettingsModel.bundleVersion(from: ["CFBundleShortVersionString": "0.1.0"]) == "0.1.0")
    }
}
