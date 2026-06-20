import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("FullDiskAccessHealthCheck")
struct FullDiskAccessHealthCheckTests {
    @Test
    func deniedProtectedDataAppendsGlobalSafetyNotification() {
        let appDelegate = makeAppDelegate()
        let result = FullDiskAccessHealthCheckResult(
            documents: Self.outcome(.granted),
            protectedData: Self.outcome(.deniedEPERM)
        )

        appDelegate.applyFullDiskAccessHealthCheckResult(result)

        let notification = appDelegate.atomStore.inboxNotification.notifications.first
        #expect(notification?.id == InboxNotification.fullDiskAccessWarningId)
        #expect(notification?.kind == .fullDiskAccessDenied)
        #expect(notification?.source == .global)
        #expect(notification?.displayLane == .safety)
        #expect(notification?.contributesToRollUpAlert == true)
        #expect(notification?.body?.contains("documents=granted") == true)
        #expect(notification?.body?.contains("protected_data=denied_eperm") == true)
    }

    @Test
    func healthyResultDismissesExistingWarning() throws {
        let appDelegate = makeAppDelegate()
        appDelegate.atomStore.inboxNotification.append(
            .fullDiskAccessDenied(
                documentsResult: .granted,
                protectedDataResult: .deniedEPERM
            ))

        appDelegate.applyFullDiskAccessHealthCheckResult(
            FullDiskAccessHealthCheckResult(
                documents: Self.outcome(.granted),
                protectedData: Self.outcome(.granted)
            ))

        let notification = try #require(appDelegate.atomStore.inboxNotification.notifications.first)
        #expect(notification.isRead == true)
        #expect(notification.isDismissedFromPaneInbox == true)
        #expect(appDelegate.atomStore.inboxNotification.globalRollUpAlertCount == 0)
    }

    @Test
    func helperUsesInjectedProbe() {
        let result = FullDiskAccessHealthCheck.evaluate {
            FullDiskAccessHealthCheckResult(
                documents: Self.outcome(.deniedEACCES),
                protectedData: Self.outcome(.deniedEPERM)
            )
        }

        #expect(result.documents.result == .deniedEACCES)
        #expect(result.protectedData.result == .deniedEPERM)
        #expect(result.isHealthy == false)
    }

    private func makeAppDelegate() -> AppDelegate {
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_TAGS": "off",
            ]),
            processIdentifier: 9001,
            timeUnixNano: { 1 }
        )
        let appDelegate = AppDelegate(
            traceRuntime: traceRuntime,
            startupTraceRecorder: AgentStudioStartupTraceRecorder(traceRuntime: traceRuntime)
        )
        appDelegate.atomStore = AtomRegistry()
        appDelegate.hasLoadedInboxNotificationStore = true
        return appDelegate
    }

    private nonisolated static func outcome(
        _ result: AgentStudioTCCAccessProbeResult
    ) -> AgentStudioTCCAccessProbeOutcome {
        AgentStudioTCCAccessProbeOutcome(
            result: result,
            commandExitClass: result == .granted ? .ok : .permissionDenied,
            rawPath: "/Users/example/Library/Messages"
        )
    }
}
