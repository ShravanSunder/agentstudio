import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxSidebarActivationResolver")
struct InboxSidebarActivationResolverTests {
    @Test
    func fullDiskAccessWarningOpensSettings() {
        let notification = InboxNotification.fullDiskAccessDenied(
            documentsResult: .granted,
            protectedDataResult: .deniedEPERM
        )

        let outcome = InboxSidebarActivationResolver.resolve(
            notification: notification,
            workspacePaneAtom: WorkspacePaneAtom()
        )

        #expect(outcome == .openFullDiskAccessSettings)
    }

    @Test
    func fullDiskAccessSettingsURLTargetsPrivacyAllFiles() {
        #expect(
            FullDiskAccessSettings.url.absoluteString
                == "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        )
    }
}
