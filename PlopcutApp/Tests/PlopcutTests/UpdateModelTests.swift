import AppKit
import Testing
@testable import Plopcut

@MainActor
@Suite struct UpdateModelTests {
    /// Records the calls Sparkle would get; a test flips `canCheckForUpdates` as Sparkle does while a check runs.
    @MainActor final class FakeUpdater: AppUpdater {
        var canCheckForUpdates = true {
            didSet { onCanCheckChange?() }
        }
        var automaticallyChecksForUpdates = false
        var onCanCheckChange: (() -> Void)?
        var checks = 0

        func checkForUpdates() { checks += 1 }
    }

    @Test func withoutAnUpdaterNothingIsOffered() {
        let model = UpdateModel(updater: nil)
        #expect(!model.isAvailable)
        #expect(!model.canCheck)
        model.check()
        model.setAutomaticChecks(true)
        #expect(!model.automaticChecks)
    }

    @Test func checkAsksTheUpdater() {
        let fake = FakeUpdater()
        let model = UpdateModel(updater: fake)
        #expect(model.isAvailable && model.canCheck)
        model.check()
        #expect(fake.checks == 1)
    }

    @Test func aRunningCheckDisablesTheCommandUntilItEnds() {
        let fake = FakeUpdater()
        let model = UpdateModel(updater: fake)
        fake.canCheckForUpdates = false
        #expect(!model.canCheck)
        model.check()
        #expect(fake.checks == 0)
        fake.canCheckForUpdates = true
        #expect(model.canCheck)
    }

    @Test func automaticChecksWriteThroughToTheUpdater() {
        let fake = FakeUpdater()
        let model = UpdateModel(updater: fake)
        #expect(!model.automaticChecks)
        model.setAutomaticChecks(true)
        #expect(fake.automaticallyChecksForUpdates)
        #expect(model.automaticChecks)
        model.setAutomaticChecks(false)
        #expect(!fake.automaticallyChecksForUpdates)
    }

    @Test func refreshPicksUpAChoiceMadeInSparklesOwnPrompt() {
        let fake = FakeUpdater()
        let model = UpdateModel(updater: fake)
        fake.automaticallyChecksForUpdates = true
        #expect(!model.automaticChecks)
        model.refresh()
        #expect(model.automaticChecks)
    }

    // A build without a public key or feed must not start Sparkle: it would alert at launch.
    @Test func sparkleStartsOnlyWithAFeedAndAKey() {
        #expect(!SparkleUpdater.isConfigured([:]))
        #expect(!SparkleUpdater.isConfigured(["SUFeedURL": "https://plopcut.com/appcast.xml"]))
        #expect(!SparkleUpdater.isConfigured(["SUFeedURL": "https://plopcut.com/appcast.xml", "SUPublicEDKey": ""]))
        #expect(SparkleUpdater.isConfigured(["SUFeedURL": "https://plopcut.com/appcast.xml", "SUPublicEDKey": "abc="]))
    }

    @Test func menuOffersCheckForUpdatesAfterTheCommands() {
        let items = MenuBarController.menuItems(failure: nil, canCheckForUpdates: true)
        #expect(items.map(\.title) == [L10n.t("saveClipboard"), L10n.t("openLibrary"), "", L10n.t("checkForUpdates")])
        #expect(items[2].isSeparatorItem)
        #expect(items[3].representedObject as? String == MenuBarAction.checkForUpdates.rawValue)
        #expect(items[3].isEnabled)
    }

    @Test func menuDisablesCheckForUpdatesWhileACheckRuns() {
        let items = MenuBarController.menuItems(failure: nil, canCheckForUpdates: false)
        #expect(items.last?.title == L10n.t("checkForUpdates"))
        #expect(items.last?.isEnabled == false)
    }

    @Test func floatingSectionStaysLastWithTheUpdateItem() {
        let items = MenuBarController.menuItems(
            failure: nil, canCheckForUpdates: true, floating: [.init(id: "a", title: "First")])
        #expect(items.map(\.title).prefix(5) == [
            L10n.t("saveClipboard"), L10n.t("openLibrary"), "", L10n.t("checkForUpdates"), "",
        ])
        #expect(items.map(\.title).last == L10n.t("closeAllFloating"))
    }

    @Test func checkForUpdatesIdIsRouted() {
        #expect(MenuBarAction(id: "check-for-updates") == .checkForUpdates)
    }
}
