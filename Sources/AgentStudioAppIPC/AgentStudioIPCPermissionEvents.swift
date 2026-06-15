import AgentStudioProgrammaticControl
import Foundation

public struct PermissionEventProjector: Sendable {
    public init() {}

    public func requestCreated(
        from record: PermissionRecord,
        occurredAt: Date = Date()
    ) -> IPCPermissionEventNotification {
        notification(name: .permissionRequestCreated, record: record, occurredAt: occurredAt)
    }

    public func requestResolved(
        from record: PermissionRecord,
        occurredAt: Date = Date()
    ) -> IPCPermissionEventNotification {
        notification(name: .permissionRequestResolved, record: record, occurredAt: occurredAt)
    }

    public func grantRevoked(
        from record: PermissionRecord,
        occurredAt: Date = Date()
    ) -> IPCPermissionEventNotification {
        notification(name: .permissionGrantRevoked, record: record, occurredAt: occurredAt)
    }

    public func grantExpired(
        from record: PermissionRecord,
        occurredAt: Date = Date()
    ) -> IPCPermissionEventNotification {
        notification(name: .permissionGrantExpired, record: record, occurredAt: occurredAt)
    }

    public func isVisible(
        _ notification: IPCPermissionEventNotification,
        to principal: IPCPrincipal
    ) -> Bool {
        let payload = notification.payload
        if payload.principalId == principal.principalId {
            return true
        }

        switch payload.approvalRoute {
        case .delegatedPrincipal(let approverId):
            guard approverId == principal.principalId else {
                return false
            }
            return Self.hasDelegatedApprovalAuthority(principal, for: payload.requestedScope)
        case .appPolicy, .humanPrompt:
            return Self.hasPolicyApprovalAuthority(principal, for: payload.requestedScope)
        }
    }

    public func isVisible(
        _ notification: IPCEventNotification,
        to principal: IPCPrincipal
    ) -> Bool {
        guard case .permission(let payload) = notification.payload else {
            return false
        }
        return isVisible(
            IPCPermissionEventNotification(
                eventId: notification.eventId,
                name: notification.name,
                occurredAt: notification.occurredAt,
                payload: payload
            ),
            to: principal
        )
    }

    private func notification(
        name: IPCEventName,
        record: PermissionRecord,
        occurredAt: Date
    ) -> IPCPermissionEventNotification {
        IPCPermissionEventNotification(
            eventId: UUID(),
            name: name,
            occurredAt: occurredAt,
            payload: IPCPermissionEventPayload(
                requestId: record.requestId,
                state: record.state,
                principalId: record.requesterPrincipalId,
                requestedScope: record.requestedScope,
                approvalRoute: record.approvalRoute
            )
        )
    }

    private static func hasDelegatedApprovalAuthority(
        _ principal: IPCPrincipal,
        for scope: IPCPermissionScope
    ) -> Bool {
        hasApprovalAuthority(principal, for: scope) { authority in
            if case .delegatedApprover(let scopes) = authority {
                return scopes
            }
            return nil
        }
    }

    private static func hasPolicyApprovalAuthority(
        _ principal: IPCPrincipal,
        for scope: IPCPermissionScope
    ) -> Bool {
        hasApprovalAuthority(principal, for: scope) { authority in
            if case .policyConfigured(let scopes) = authority {
                return scopes
            }
            return nil
        }
    }

    private static func hasApprovalAuthority(
        _ principal: IPCPrincipal,
        for scope: IPCPermissionScope,
        scopesForAuthority: (IPCApprovalAuthority) -> Set<IPCApprovalScope>?
    ) -> Bool {
        let approvalScope = IPCApprovalScope(
            privilege: scope.privilege,
            target: scope.target,
            dataScope: scope.dataScope
        )
        return scopesForAuthority(principal.approvalAuthority)?.contains(approvalScope) ?? false
    }
}
