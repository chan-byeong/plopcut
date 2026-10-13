import Foundation
import Testing
@testable import Plopcut

private struct FakeChecker: PermissionChecking {
    var accessibility: Bool
    var clipboard: Bool?
    func accessibilityTrusted() -> Bool { accessibility }
    func clipboardReadable() -> Bool? { clipboard }
}

@MainActor
@Suite struct PermissionsModelTests {
    private func model(_ checker: FakeChecker) -> PermissionsModel {
        L10n.languageOverride = "ko"
        return PermissionsModel(checker: checker, openURL: { _ in })
    }

    // A-01
    @Test func accessibilityFollowsTheTrustCheck() {
        #expect(model(FakeChecker(accessibility: true, clipboard: true)).status(of: .accessibility) == .granted)
        #expect(model(FakeChecker(accessibility: false, clipboard: true)).status(of: .accessibility) == .missing)
    }

    // A-02
    @Test func clipboardIsGrantedMissingOrUnknown() {
        #expect(model(FakeChecker(accessibility: true, clipboard: true)).status(of: .clipboard) == .granted)
        #expect(model(FakeChecker(accessibility: true, clipboard: false)).status(of: .clipboard) == .missing)
        #expect(model(FakeChecker(accessibility: true, clipboard: nil)).status(of: .clipboard) == .unknown)
    }

    // A-03
    @Test func automationIsAlwaysUnknown() {
        #expect(model(FakeChecker(accessibility: true, clipboard: true)).status(of: .automation) == .unknown)
        #expect(model(FakeChecker(accessibility: false, clipboard: false)).status(of: .automation) == .unknown)
    }

    // N-04
    @Test func detailKeysFollowItemAndStatusAndUnknownIsShared() {
        #expect(PermissionsModel.detailKey(.accessibility, .granted) == "permissionAccessibilityGranted")
        #expect(PermissionsModel.detailKey(.accessibility, .missing) == "permissionAccessibilityMissing")
        #expect(PermissionsModel.detailKey(.clipboard, .granted) == "permissionClipboardGranted")
        #expect(PermissionsModel.detailKey(.clipboard, .missing) == "permissionClipboardMissing")
        #expect(PermissionsModel.detailKey(.automation, .granted) == "permissionAutomationGranted")
        #expect(PermissionsModel.detailKey(.automation, .missing) == "permissionAutomationMissing")
        for item in PermissionItem.allCases {
            #expect(PermissionsModel.detailKey(item, .unknown) == "permissionUnknownDetail")
        }
    }

    @Test func everyDetailAndStatusKeyHasBothLanguages() {
        for item in PermissionItem.allCases {
            for status in [PermissionStatus.granted, .missing, .unknown] {
                let key = PermissionsModel.detailKey(item, status)
                #expect(StringTable.entries[key] != nil, "\(key)")
                #expect(StringTable.entries[PermissionsModel.statusKey(status)] != nil)
            }
        }
        #expect(StringTable.entries["permissionAutomationNote"] != nil)
        #expect(StringTable.entries["openSystemSettings"] != nil)
    }

    // The next action only exists where the user can do something about it.
    @Test func onlyAMissingAccessibilityOffersTheSystemSettingsButton() {
        let missing = model(FakeChecker(accessibility: false, clipboard: true))
        #expect(missing.offersSystemSettings(for: .accessibility))
        #expect(!missing.offersSystemSettings(for: .clipboard))
        #expect(!missing.offersSystemSettings(for: .automation))
        let granted = model(FakeChecker(accessibility: true, clipboard: true))
        #expect(!granted.offersSystemSettings(for: .accessibility))
    }

    @Test func openingSystemSettingsUsesTheAccessibilityPane() {
        var opened: URL?
        let sut = PermissionsModel(checker: FakeChecker(accessibility: false, clipboard: true), openURL: { opened = $0 })
        sut.openAccessibilitySettings()
        #expect(opened?.absoluteString == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    // A-04 / the screen refreshes when the user comes back from System Settings.
    @Test func refreshPicksUpAChangedPermission() {
        final class Box: @unchecked Sendable { var trusted = false }
        struct Live: PermissionChecking {
            let box: Box
            func accessibilityTrusted() -> Bool { box.trusted }
            func clipboardReadable() -> Bool? { true }
        }
        let box = Box()
        let sut = PermissionsModel(checker: Live(box: box), openURL: { _ in })
        #expect(sut.status(of: .accessibility) == .missing)
        box.trusted = true
        sut.refresh()
        #expect(sut.status(of: .accessibility) == .granted)
    }
}
