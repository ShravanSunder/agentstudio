import Testing

@testable import AgentStudio

@Suite("PaneInboxAutoClearPolicy")
struct PaneInboxAutoClearPolicyTests {
    @Test("auto-clears passive activity notifications")
    func autoClearsPassiveActivityNotifications() {
        let policy = PaneInboxAutoClearPolicy()

        #expect(policy.canAutoClear(kind: .agentDesktopNotification))
        #expect(policy.canAutoClear(kind: .bellRang))
        #expect(policy.canAutoClear(kind: .commandFinished))
        #expect(policy.canAutoClear(kind: .agentRpc))
    }

    @Test("keeps user-action and failure notifications visible")
    func keepsUserActionAndFailureNotificationsVisible() {
        let policy = PaneInboxAutoClearPolicy()

        #expect(policy.canAutoClear(kind: .approvalRequested) == false)
        #expect(policy.canAutoClear(kind: .securityEvent) == false)
        #expect(policy.canAutoClear(kind: .persistenceRecovery) == false)
        #expect(policy.canAutoClear(kind: .terminalProgressError) == false)
        #expect(policy.canAutoClear(kind: .terminalRendererUnhealthy) == false)
        #expect(policy.canAutoClear(kind: .terminalSecureInputRequested) == false)
    }
}
