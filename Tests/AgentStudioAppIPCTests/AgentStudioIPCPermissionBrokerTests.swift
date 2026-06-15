import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("AgentStudio IPC permission broker")
struct AgentStudioIPCPermissionBrokerTests {
    @Test("app policy auto-approve records an active canonical grant")
    func appPolicyAutoApproveRecordsActiveCanonicalGrant() throws {
        let ledger = GrantLedger()
        let broker = PermissionBroker(
            grantLedger: ledger,
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: StaticApprovalPolicyStore(decision: .approve)
        )
        let requester = makePermissionPrincipal(boundPaneId: "pane-1")
        let params = IPCPermissionRequestParams(
            scope: IPCPermissionScope(
                privilege: .terminalInputWrite, target: .pane("pane-2"), dataScope: .terminalInput),
            reason: "paired pane",
            approvalRoute: .appPolicy
        )

        let result = try broker.requestPermission(params, requester: requester)

        #expect(result.state == .granted)
        #expect(ledger.contains(params.scope, for: requester.principalId))
    }

    @Test("approved grants derive data scope from privilege")
    func approvedGrantsDeriveDataScopeFromPrivilege() throws {
        let ledger = GrantLedger()
        let broker = PermissionBroker(
            grantLedger: ledger,
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: StaticApprovalPolicyStore(decision: .approve)
        )
        let requester = makePermissionPrincipal(boundPaneId: "pane-1")
        let requestedScope = IPCPermissionScope(
            privilege: .terminalInputWrite,
            target: .pane("pane-2"),
            dataScope: .unspecified
        )
        let canonicalScope = IPCPermissionScope(
            privilege: .terminalInputWrite,
            target: .pane("pane-2"),
            dataScope: .terminalInput
        )

        let result = try broker.requestPermission(
            IPCPermissionRequestParams(scope: requestedScope, reason: "paired pane", approvalRoute: .appPolicy),
            requester: requester
        )

        #expect(result.state == .granted)
        #expect(ledger.contains(canonicalScope, for: requester.principalId))
        #expect(!ledger.contains(requestedScope, for: requester.principalId))
    }

    @Test("app policy ask leaves request pending")
    func appPolicyAskLeavesRequestPending() throws {
        let broker = PermissionBroker(
            grantLedger: GrantLedger(),
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: StaticApprovalPolicyStore(decision: .ask)
        )
        let requester = makePermissionPrincipal(boundPaneId: "pane-1")

        let result = try broker.requestPermission(
            IPCPermissionRequestParams(
                scope: IPCPermissionScope(
                    privilege: .terminalInputWrite, target: .pane("pane-2"), dataScope: .terminalInput),
                reason: "paired pane",
                approvalRoute: .appPolicy
            ),
            requester: requester
        )

        #expect(result.state == .pending)
        #expect(try broker.requestStatus(result.requestId, requester: requester).state == .pending)
    }

    @Test("human approval port can resolve prompt requests")
    func humanApprovalPortCanResolvePromptRequests() throws {
        let ledger = GrantLedger()
        let broker = PermissionBroker(
            grantLedger: ledger,
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: StaticApprovalPolicyStore(decision: .ask),
            humanApprovalPort: StaticHumanApprovalPort(decision: .approve)
        )
        let requester = makePermissionPrincipal(boundPaneId: "pane-1")
        let scope = IPCPermissionScope(
            privilege: .terminalInputWrite, target: .pane("pane-2"), dataScope: .terminalInput)

        let result = try broker.requestPermission(
            IPCPermissionRequestParams(
                scope: scope,
                reason: "paired pane",
                approvalRoute: .humanPrompt
            ),
            requester: requester
        )

        #expect(result.state == .granted)
        #expect(ledger.contains(scope, for: requester.principalId))
    }

    @Test("delegated approver can list and resolve routed requests")
    func delegatedApproverCanListAndResolveRoutedRequests() throws {
        let ledger = GrantLedger()
        let broker = PermissionBroker(
            grantLedger: ledger,
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: StaticApprovalPolicyStore(decision: .ask)
        )
        let requester = makePermissionPrincipal(boundPaneId: "pane-1")
        let scope = IPCPermissionScope(
            privilege: .terminalInputWrite, target: .pane("pane-2"), dataScope: .terminalInput)
        let approver = makePermissionApprover(scope: scope)

        let result = try broker.requestPermission(
            IPCPermissionRequestParams(
                scope: scope, reason: "paired pane", approvalRoute: .delegatedPrincipal(approver.principalId)),
            requester: requester
        )

        #expect(try broker.pendingApprovals(for: approver).map(\.requestId) == [result.requestId])
        let resolved = try broker.resolveRequest(result.requestId, approver: approver, decision: .approve)

        #expect(resolved.state == .granted)
        #expect(ledger.contains(scope, for: requester.principalId))
    }

    @Test("delegated approver authority is scoped by requested privilege")
    func delegatedApproverAuthorityIsScopedByRequestedPrivilege() throws {
        let broker = PermissionBroker(
            grantLedger: GrantLedger(),
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: StaticApprovalPolicyStore(decision: .ask)
        )
        let requester = makePermissionPrincipal(boundPaneId: "pane-1")
        let requestedScope = IPCPermissionScope(
            privilege: .terminalInputWrite, target: .pane("pane-2"), dataScope: .terminalInput)
        let mismatchedApprover = makePermissionApprover(
            scope: IPCPermissionScope(
                privilege: .terminalSnapshotRead,
                target: .pane("pane-2"),
                dataScope: .terminalSnapshot
            )
        )

        let result = try broker.requestPermission(
            IPCPermissionRequestParams(
                scope: requestedScope,
                reason: "paired pane",
                approvalRoute: .delegatedPrincipal(mismatchedApprover.principalId)
            ),
            requester: requester
        )

        #expect(try broker.pendingApprovals(for: mismatchedApprover).isEmpty)
        #expect(throws: PermissionBrokerError.self) {
            try broker.resolveRequest(result.requestId, approver: mismatchedApprover, decision: .approve)
        }
    }

    @Test("rejects self approval and unauthorized delegated approval")
    func rejectsSelfApprovalAndUnauthorizedDelegatedApproval() throws {
        let broker = PermissionBroker(
            grantLedger: GrantLedger(),
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: StaticApprovalPolicyStore(decision: .ask)
        )
        let scope = IPCPermissionScope(
            privilege: .terminalInputWrite, target: .pane("pane-2"), dataScope: .terminalInput)
        let requester = makePermissionApprover(scope: scope)

        let result = try broker.requestPermission(
            IPCPermissionRequestParams(
                scope: scope, reason: "paired pane", approvalRoute: .delegatedPrincipal(requester.principalId)),
            requester: requester
        )

        #expect(throws: PermissionBrokerError.self) {
            try broker.resolveRequest(result.requestId, approver: requester, decision: .approve)
        }

        let unauthorized = makePermissionPrincipal(boundPaneId: "pane-3")
        #expect(throws: PermissionBrokerError.self) {
            try broker.resolveRequest(result.requestId, approver: unauthorized, decision: .approve)
        }
    }
}

private struct StaticApprovalPolicyStore: ApprovalPolicyStore {
    let decision: ApprovalPolicyDecision

    func decision(for _: PermissionRecord, requester _: IPCPrincipal) -> ApprovalPolicyDecision {
        decision
    }
}

private struct StaticHumanApprovalPort: AppIPCPermissionApprovalPort {
    let decision: ApprovalPolicyDecision

    func decision(for _: PermissionRecord, requester _: IPCPrincipal) -> ApprovalPolicyDecision {
        decision
    }
}

private func makePermissionPrincipal(boundPaneId: String) -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUID(),
        runtimeId: UUID(),
        accessMode: .agentStudioOnly,
        kind: .spawnedPaneAgent(boundPaneId: boundPaneId, boundWorkspaceId: nil),
        approvalAuthority: .noApprovalAuthority
    )
}

private func makePermissionApprover(scope: IPCPermissionScope) -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUID(),
        runtimeId: UUID(),
        accessMode: .agentStudioOnly,
        kind: .spawnedPaneAgent(boundPaneId: "approver", boundWorkspaceId: nil),
        approvalAuthority: .delegatedApprover(
            scopes: [IPCApprovalScope(privilege: scope.privilege, target: scope.target, dataScope: scope.dataScope)]
        )
    )
}
