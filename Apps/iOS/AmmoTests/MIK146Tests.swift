import SwiftUI
import Testing

@testable import Ammo

/// The snapshot shield must cover the app-switcher capture without blanking the
/// app for every system gesture that merely deactivates the scene.
@Suite("MIK-146 snapshot privacy shield")
struct MIK146Tests {
    @Test("The visible app is never shielded")
    func activeIsNotShielded() {
        #expect(!SnapshotPrivacyPolicy.shieldsContent(in: .active))
    }

    @Test("A Notification Centre or Control Centre pull leaves the UI intact")
    func inactiveIsNotShielded() {
        #expect(!SnapshotPrivacyPolicy.shieldsContent(in: .inactive))
    }

    @Test("Backgrounding shields the content iOS is about to snapshot")
    func backgroundIsShielded() {
        #expect(SnapshotPrivacyPolicy.shieldsContent(in: .background))
    }
}
