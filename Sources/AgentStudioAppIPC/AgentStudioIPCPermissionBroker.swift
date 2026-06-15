import AgentStudioProgrammaticControl
import Foundation

public enum ApprovalPolicyDecision: String, Equatable, Sendable {
    case approve
    case deny
    case ask
}

public protocol ApprovalPolicyStore: Sendable {
    func decision(for record: PermissionRecord, requester: IPCPrincipal) -> ApprovalPolicyDecision
}

public struct PermissionRecord: Equatable, Sendable {
    public let requestId: UUID
    public let requesterPrincipalId: UUID
    public let requestedScope: IPCPermissionScope
    public let reason: String
    public let approvalRoute: IPCPermissionApprovalRoute
    public let state: IPCPermissionRequestState

    public init(
        requestId: UUID,
        requesterPrincipalId: UUID,
        requestedScope: IPCPermissionScope,
        reason: String,
        approvalRoute: IPCPermissionApprovalRoute,
        state: IPCPermissionRequestState
    ) {
        self.requestId = requestId
        self.requesterPrincipalId = requesterPrincipalId
        self.requestedScope = requestedScope
        self.reason = reason
        self.approvalRoute = approvalRoute
        self.state = state
    }

    public var result: IPCPermissionRequestResult {
        IPCPermissionRequestResult(
            requestId: requestId,
            state: state,
            principalId: requesterPrincipalId,
            requestedScope: requestedScope,
            approvalRoute: approvalRoute
        )
    }

    public func replacingState(_ state: IPCPermissionRequestState) -> Self {
        Self(
            requestId: requestId,
            requesterPrincipalId: requesterPrincipalId,
            requestedScope: requestedScope,
            reason: reason,
            approvalRoute: approvalRoute,
            state: state
        )
    }
}

public struct PermissionBrokerError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case requestNotFound
        case requesterMismatch
        case requestNotPending
        case unauthorizedApprover
        case selfApprovalNotAllowed
        case unsupportedResolutionDecision
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
    }
}

public struct PermissionBroker: Sendable {
    private let grantLedger: GrantLedger
    private let canonicalizer: PermissionScopeCanonicalizer
    private let approvalPolicyStore: any ApprovalPolicyStore
    private let humanApprovalPort: (any AppIPCPermissionApprovalPort)?

    public init(
        grantLedger: GrantLedger,
        canonicalizer: PermissionScopeCanonicalizer,
        approvalPolicyStore: any ApprovalPolicyStore,
        humanApprovalPort: (any AppIPCPermissionApprovalPort)? = nil
    ) {
        self.grantLedger = grantLedger
        self.canonicalizer = canonicalizer
        self.approvalPolicyStore = approvalPolicyStore
        self.humanApprovalPort = humanApprovalPort
    }

    public func requestPermission(
        _ params: IPCPermissionRequestParams,
        requester: IPCPrincipal
    ) throws -> IPCPermissionRequestResult {
        let canonicalScope = try canonicalizer.canonicalize(params.scope, for: requester)
        let pendingRecord = PermissionRecord(
            requestId: UUID(),
            requesterPrincipalId: requester.principalId,
            requestedScope: canonicalScope,
            reason: params.reason,
            approvalRoute: params.approvalRoute,
            state: .pending
        )

        let resolvedRecord = try resolveInitialRecord(pendingRecord, requester: requester)
        grantLedger.recordPermissionRequest(resolvedRecord)
        if resolvedRecord.state == .granted {
            grantLedger.grant(resolvedRecord.requestedScope, to: requester.principalId)
        }

        return resolvedRecord.result
    }

    public func requestStatus(_ requestId: UUID, requester: IPCPrincipal) throws -> IPCPermissionRequestResult {
        guard let record = grantLedger.permissionRecord(requestId: requestId) else {
            throw PermissionBrokerError(reason: .requestNotFound)
        }
        guard record.requesterPrincipalId == requester.principalId else {
            throw PermissionBrokerError(reason: .requesterMismatch)
        }
        return record.result
    }

    public func pendingApprovals(for approver: IPCPrincipal) throws -> [PermissionRecord] {
        grantLedger.permissionRecords()
            .filter { record in
                record.state == .pending
                    && record.approvalRoute == .delegatedPrincipal(approver.principalId)
                    && canApprove(approver: approver, record: record)
            }
            .sorted { $0.requestId.uuidString < $1.requestId.uuidString }
    }

    public func resolveRequest(
        _ requestId: UUID,
        approver: IPCPrincipal,
        decision: ApprovalPolicyDecision
    ) throws -> IPCPermissionRequestResult {
        guard decision == .approve || decision == .deny else {
            throw PermissionBrokerError(reason: .unsupportedResolutionDecision)
        }
        guard let record = grantLedger.permissionRecord(requestId: requestId) else {
            throw PermissionBrokerError(reason: .requestNotFound)
        }
        guard record.state == .pending else {
            throw PermissionBrokerError(reason: .requestNotPending)
        }
        guard record.requesterPrincipalId != approver.principalId else {
            throw PermissionBrokerError(reason: .selfApprovalNotAllowed)
        }
        guard record.approvalRoute == .delegatedPrincipal(approver.principalId),
            canApprove(approver: approver, record: record)
        else {
            throw PermissionBrokerError(reason: .unauthorizedApprover)
        }

        let state: IPCPermissionRequestState = decision == .approve ? .granted : .denied
        let resolvedRecord = record.replacingState(state)
        grantLedger.updatePermissionRecord(resolvedRecord)
        if state == .granted {
            grantLedger.grant(resolvedRecord.requestedScope, to: record.requesterPrincipalId)
        }
        return resolvedRecord.result
    }

    private func resolveInitialRecord(_ record: PermissionRecord, requester: IPCPrincipal) throws -> PermissionRecord {
        switch record.approvalRoute {
        case .appPolicy:
            switch approvalPolicyStore.decision(for: record, requester: requester) {
            case .approve:
                return record.replacingState(.granted)
            case .deny:
                return record.replacingState(.denied)
            case .ask:
                return record
            }
        case .humanPrompt:
            guard let humanApprovalPort else {
                return record
            }
            switch humanApprovalPort.decision(for: record, requester: requester) {
            case .approve:
                return record.replacingState(.granted)
            case .deny:
                return record.replacingState(.denied)
            case .ask:
                return record
            }
        case .delegatedPrincipal:
            return record
        }
    }

    private func canApprove(approver: IPCPrincipal, record: PermissionRecord) -> Bool {
        switch approver.approvalAuthority {
        case .delegatedApprover(let scopes), .policyConfigured(let scopes):
            scopes.contains(
                IPCApprovalScope(
                    privilege: record.requestedScope.privilege,
                    target: record.requestedScope.target,
                    dataScope: record.requestedScope.dataScope
                )
            )
        case .noApprovalAuthority:
            false
        }
    }
}
