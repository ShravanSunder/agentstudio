import Foundation

extension InboxNotification {
    static let fullDiskAccessWarningId = UUID(uuidString: "D15CACC5-A9E5-4E61-9D42-23D1F7D1A11F")!

    static func fullDiskAccessDenied(
        documentsResult: AgentStudioTCCAccessProbeResult,
        protectedDataResult: AgentStudioTCCAccessProbeResult
    ) -> InboxNotification {
        InboxNotification(
            id: fullDiskAccessWarningId,
            timestamp: Date(),
            kind: .fullDiskAccessDenied,
            title: "Full Disk Access needs attention",
            body: fullDiskAccessNotificationBody(
                documentsResult: documentsResult,
                protectedDataResult: protectedDataResult
            ),
            source: .global,
            isRead: false,
            isDismissedFromPaneInbox: false
        )
    }

    private static func fullDiskAccessNotificationBody(
        documentsResult: AgentStudioTCCAccessProbeResult,
        protectedDataResult: AgentStudioTCCAccessProbeResult
    ) -> String {
        "AgentStudio can launch, but child terminals cannot read protected data. Enable or re-enable Full Disk Access for this AgentStudio app in System Settings. Probe results: documents=\(documentsResult.rawValue), protected_data=\(protectedDataResult.rawValue)."
    }
}
