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

    @Test("requester recovers missed permission request and grant state through status queries")
    func requesterRecoversMissedPermissionStateThroughStatusQueries() throws {
        let ledger = GrantLedger()
        let broker = PermissionBroker(
            grantLedger: ledger,
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: StaticApprovalPolicyStore(decision: .approve)
        )
        let requester = makePermissionPrincipal(boundPaneId: "pane-1")
        let scope = IPCPermissionScope(
            privilege: .terminalInputWrite,
            target: .pane("pane-2"),
            dataScope: .terminalInput
        )

        let request = try broker.requestPermission(
            IPCPermissionRequestParams(scope: scope, reason: "paired pane", approvalRoute: .appPolicy),
            requester: requester
        )
        let requestStatus = try broker.requestStatus(request.requestId, requester: requester)
        let grantStatus = try broker.grantStatus(request.requestId, requester: requester)

        #expect(requestStatus.state == .granted)
        #expect(grantStatus.state == .granted)
        #expect(grantStatus.active)

        ledger.revokeAll(for: requester.principalId)
        let revokedStatus = try broker.grantStatus(request.requestId, requester: requester)
        #expect(revokedStatus.state == .granted)
        #expect(!revokedStatus.active)
    }

    @Test("request and grant status are requester-scoped")
    func requestAndGrantStatusAreRequesterScoped() throws {
        let ledger = GrantLedger()
        let broker = PermissionBroker(
            grantLedger: ledger,
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: StaticApprovalPolicyStore(decision: .approve)
        )
        let requester = makePermissionPrincipal(boundPaneId: "pane-1")
        let unrelated = makePermissionPrincipal(boundPaneId: "pane-3")
        let result = try broker.requestPermission(
            IPCPermissionRequestParams(
                scope: IPCPermissionScope(
                    privilege: .terminalInputWrite,
                    target: .pane("pane-2"),
                    dataScope: .terminalInput
                ),
                reason: "paired pane",
                approvalRoute: .appPolicy
            ),
            requester: requester
        )

        #expect(throws: PermissionBrokerError.self) {
            try broker.requestStatus(result.requestId, requester: unrelated)
        }
        #expect(throws: PermissionBrokerError.self) {
            try broker.grantStatus(result.requestId, requester: unrelated)
        }
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

    @Test("permission event visibility includes requester and routed approver only")
    func permissionEventVisibilityIncludesRequesterAndRoutedApproverOnly() throws {
        let ledger = GrantLedger()
        let broker = PermissionBroker(
            grantLedger: ledger,
            canonicalizer: PermissionScopeCanonicalizer(),
            approvalPolicyStore: StaticApprovalPolicyStore(decision: .ask)
        )
        let requester = makePermissionPrincipal(boundPaneId: "pane-1")
        let scope = IPCPermissionScope(
            privilege: .terminalInputWrite,
            target: .pane("pane-2"),
            dataScope: .terminalInput
        )
        let approver = makePermissionApprover(scope: scope)
        let unrelated = makePermissionPrincipal(boundPaneId: "pane-3")
        let result = try broker.requestPermission(
            IPCPermissionRequestParams(
                scope: scope,
                reason: "paired pane",
                approvalRoute: .delegatedPrincipal(approver.principalId)
            ),
            requester: requester
        )
        let record = try #require(ledger.permissionRecord(requestId: result.requestId))
        let notification = PermissionEventProjector().requestCreated(from: record)

        #expect(PermissionEventProjector().isVisible(notification, to: requester))
        #expect(PermissionEventProjector().isVisible(notification, to: approver))
        #expect(!PermissionEventProjector().isVisible(notification, to: unrelated))
    }

    @Test("permission event visibility includes configured app approval authority")
    func permissionEventVisibilityIncludesConfiguredAppApprovalAuthority() throws {
        let projector = PermissionEventProjector()
        let scope = IPCPermissionScope(
            privilege: .terminalInputWrite,
            target: .pane("pane-2"),
            dataScope: .terminalInput
        )
        let requester = makePermissionPrincipal(boundPaneId: "pane-1")
        let appApprovalPrincipal = makePolicyApprovalPrincipal(scope: scope)
        let mismatchedApprovalPrincipal = makePolicyApprovalPrincipal(
            scope: IPCPermissionScope(
                privilege: .terminalSnapshotRead,
                target: .pane("pane-2"),
                dataScope: .terminalSnapshot
            )
        )
        let record = PermissionRecord(
            requestId: UUID(),
            requesterPrincipalId: requester.principalId,
            requestedScope: scope,
            reason: "needs app approval",
            approvalRoute: .humanPrompt,
            state: .pending
        )
        let notification = projector.requestCreated(from: record)

        #expect(projector.isVisible(notification, to: requester))
        #expect(projector.isVisible(notification, to: appApprovalPrincipal))
        #expect(!projector.isVisible(notification, to: mismatchedApprovalPrincipal))
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

private func makePolicyApprovalPrincipal(scope: IPCPermissionScope) -> IPCPrincipal {
    IPCPrincipal(
        principalId: UUID(),
        runtimeId: UUID(),
        accessMode: .agentStudioOnly,
        kind: .automationClient,
        approvalAuthority: .policyConfigured(
            scopes: [IPCApprovalScope(privilege: scope.privilege, target: scope.target, dataScope: scope.dataScope)]
        )
    )
}
