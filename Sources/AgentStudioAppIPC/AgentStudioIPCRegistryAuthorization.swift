import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

package struct AppIPCMethodRegistry: Sendable {
    package let channel: AgentStudioIPCChannel
    package let capabilities: IPCMethodCatalogResult
    /// The one cache behind `system.capabilities`. Held so a test that drives
    /// the real socket can prove the catalog is composed and encoded once and
    /// served from the stored value thereafter.
    package let capabilitiesTransportResultCache: AppIPCCachedTransportResult
    private let registrationsByName: [String: AnyAppIPCMethodRegistration]

    package init(registrations: [AnyAppIPCMethodRegistration], channel: AgentStudioIPCChannel) throws {
        var seenNames: Set<String> = []
        for registration in registrations {
            let name = registration.descriptor.metadata.name
            guard seenNames.insert(name).inserted else {
                throw AppIPCMethodRegistryError.duplicateMethodName(name)
            }
        }
        let available = registrations.filter {
            $0.descriptor.metadata.exposure == .allChannels || channel == .debug
        }
        guard let ping = available.first(where: { $0.descriptor.metadata.name == "system.ping" }) else {
            throw AppIPCMethodRegistryError.missingSystemPing
        }
        let composition = try IPCSystemCapabilitiesDescriptorFactory.compose(
            compatibility: .current, availableDescriptors: available.map(\.descriptor),
            illustrativeDescriptor: ping.descriptor
        )
        let capabilityDescriptor = composition.descriptor
        let capabilityResult = composition.result
        let capabilitiesTransportResultCache = AppIPCCachedTransportResult {
            try JSONDecoder().decode(
                JSONValue.self, from: try capabilityDescriptor.encodeResult(capabilityResult))
        }
        let capabilityRegistration = try AppIPCTypedMethodRegistration(
            descriptor: composition.descriptor,
            correlation: .notRequired,
            resolveTarget: { parameters, context, _ in
                try AppIPCBuiltInRegistrationSupport.principalTarget(parameters, context: context)
            },
            connectionHandler: { _, _, _ in capabilityResult },
            cachedTransportResult: capabilitiesTransportResultCache
        ).erase()
        self.capabilitiesTransportResultCache = capabilitiesTransportResultCache
        self.channel = channel
        self.capabilities = composition.result
        self.registrationsByName = Dictionary(
            uniqueKeysWithValues: (available + [capabilityRegistration]).map { ($0.descriptor.metadata.name, $0) }
        )
    }

    package func registration(named methodName: String) -> AnyAppIPCMethodRegistration? {
        registrationsByName[methodName]
    }
}

package enum AppIPCMethodRegistryError: Error, Equatable, Sendable {
    case duplicateMethodName(String)
    case missingSystemPing
}

public struct AuthorizationError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case methodNotFound
        case unauthorized
        case noBoundPane
        case missingGrant
    }

    public let reason: Reason
    public let requiredScope: IPCPermissionScope?

    public init(reason: Reason, requiredScope: IPCPermissionScope? = nil) {
        self.reason = reason
        self.requiredScope = requiredScope
    }
}

public final class GrantLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var grantsByPrincipalId: [UUID: Set<IPCPermissionScope>] = [:]
    private var permissionRecordsById: [UUID: PermissionRecord] = [:]

    public init() {}

    public func grant(_ scope: IPCPermissionScope, to principalId: UUID) {
        lock.withLock {
            _ = grantsByPrincipalId[principalId, default: []].insert(scope)
        }
    }

    public func contains(_ scope: IPCPermissionScope, for principalId: UUID) -> Bool {
        lock.withLock {
            grantsByPrincipalId[principalId, default: []].contains(scope)
        }
    }

    public func revokeAll(for principalId: UUID) {
        lock.withLock {
            _ = grantsByPrincipalId.removeValue(forKey: principalId)
        }
    }

    public func revokeAll() {
        lock.withLock {
            grantsByPrincipalId.removeAll(keepingCapacity: false)
        }
    }

    public func recordPermissionRequest(_ record: PermissionRecord) {
        lock.withLock {
            permissionRecordsById[record.requestId] = record
        }
    }

    public func permissionRecord(requestId: UUID) -> PermissionRecord? {
        lock.withLock {
            permissionRecordsById[requestId]
        }
    }

    public func updatePermissionRecord(_ record: PermissionRecord) {
        lock.withLock {
            permissionRecordsById[record.requestId] = record
        }
    }

    public func permissionRecords() -> [PermissionRecord] {
        lock.withLock {
            Array(permissionRecordsById.values)
        }
    }

    public func resolvePendingPermissionRecord(
        requestId: UUID,
        approver: IPCPrincipal,
        decision: ApprovalPolicyDecision,
        canApprove: (PermissionRecord) -> Bool
    ) throws -> PermissionRecord {
        try lock.withLock {
            guard decision == .approve || decision == .deny else {
                throw PermissionBrokerError(reason: .unsupportedResolutionDecision)
            }
            guard let record = permissionRecordsById[requestId] else {
                throw PermissionBrokerError(reason: .requestNotFound)
            }
            guard record.state == .pending else {
                throw PermissionBrokerError(reason: .requestNotPending)
            }
            guard record.requesterPrincipalId != approver.principalId else {
                throw PermissionBrokerError(reason: .selfApprovalNotAllowed)
            }
            guard record.approvalRoute == .delegatedPrincipal(approver.principalId),
                canApprove(record)
            else {
                throw PermissionBrokerError(reason: .unauthorizedApprover)
            }

            let state: IPCPermissionRequestState = decision == .approve ? .granted : .denied
            let resolvedRecord = record.replacingState(state)
            permissionRecordsById[requestId] = resolvedRecord
            if state == .granted {
                _ = grantsByPrincipalId[record.requesterPrincipalId, default: []].insert(record.requestedScope)
            } else {
                grantsByPrincipalId[record.requesterPrincipalId]?.remove(record.requestedScope)
            }
            return resolvedRecord
        }
    }
}

public struct PermissionScopeCanonicalizer: Sendable {
    public init() {}

    public func canonicalize(_ scope: IPCPermissionScope, for principal: IPCPrincipal) throws -> IPCPermissionScope {
        let target: IPCTargetScope
        switch scope.target {
        case .selfPane:
            guard let boundPaneId = principal.boundPaneId else {
                throw AuthorizationError(reason: .noBoundPane)
            }
            target = .pane(boundPaneId)
        case .pane, .workspace, .app:
            target = scope.target
        }

        return IPCPermissionScope(
            privilege: scope.privilege,
            target: target,
            dataScope: scope.dataScope == .unspecified
                ? Self.dataScope(for: scope.privilege)
                : scope.dataScope
        )
    }

    public static func dataScope(for privilege: IPCPrivilegeClass) -> IPCDataScope {
        switch privilege {
        case .systemRead, .workspaceRead:
            .unspecified
        case .paneContextRead, .layoutMutate:
            .paneContext
        case .bridgeRead, .bridgeControl:
            .bridgeReviewPackage
        case .bridgeContentRead:
            .bridgeContent
        case .bridgeTelemetryRead, .bridgeTelemetryFlush:
            .bridgeTelemetry
        case .uiPresent:
            .uiSurface
        case .terminalRead, .terminalSnapshotRead:
            .terminalSnapshot
        case .terminalWrite, .terminalInputWrite:
            .terminalInput
        case .terminalStatusRead:
            .terminalStatus
        case .terminalWait:
            .terminalWait
        case .eventsRead, .permissionRequest, .permissionRead, .grantApprove:
            .permissionState
        case .appCommandExecute:
            .unspecified
        case .sidebarStateMutate:
            .sidebarState
        case .sessionReportWrite:
            .sessionReport
        case .sessionStateRead:
            .sessionState
        case .debugUnsafe:
            .unspecified
        }
    }
}

public struct AuthorizationService: Sendable {
    private let methodRegistry: AppIPCMethodRegistry
    private let grantLedger: GrantLedger
    private let canonicalizer: PermissionScopeCanonicalizer

    package init(
        methodRegistry: AppIPCMethodRegistry,
        grantLedger: GrantLedger,
        canonicalizer: PermissionScopeCanonicalizer
    ) {
        self.methodRegistry = methodRegistry
        self.grantLedger = grantLedger
        self.canonicalizer = canonicalizer
    }

    package func authorize(principal: IPCPrincipal, request: AppIPCMethodAuthorizationRequest) throws {
        guard let registration = methodRegistry.registration(named: request.methodName) else {
            throw AuthorizationError(reason: .methodNotFound)
        }
        let metadata = registration.descriptor.metadata
        guard Set(metadata.requiredPrivileges) == request.requiredPrivileges,
            metadata.dataScope == request.dataScope
        else {
            throw AuthorizationError(reason: .unauthorized)
        }
        if isDiagnostic(principal), methodRegistry.channel == .debug {
            return
        }
        guard metadata.exposure == .allChannels else { throw AuthorizationError(reason: .unauthorized) }
        for privilege in request.requiredPrivileges {
            try authorize(
                principal: principal,
                scope: IPCPermissionScope(
                    privilege: privilege, target: request.target, dataScope: request.dataScope
                ))
        }
        for scope in request.additionalScopes {
            try authorize(principal: principal, scope: scope)
        }
    }

    private func isDiagnostic(_ principal: IPCPrincipal) -> Bool {
        switch (principal.kind, principal.accessMode) {
        case (.automationClient, .automationSameUser),
            (.unsafeDebugClient, .unsafeDebug):
            true
        case (.automationClient, _),
            (.unsafeDebugClient, _),
            (.spawnedPaneAgent, _),
            (.futureMCPClient, _):
            false
        }
    }

    public func authorize(
        principal: IPCPrincipal,
        scope: IPCPermissionScope
    ) throws {
        let canonicalScope = try canonicalizer.canonicalize(scope, for: principal)

        if baselineAllows(canonicalScope, for: principal) {
            return
        }

        if canonicalScope.privilege == .debugUnsafe {
            throw AuthorizationError(reason: .unauthorized)
        }

        if grantLedger.contains(canonicalScope, for: principal.principalId) {
            return
        }

        throw AuthorizationError(reason: .missingGrant, requiredScope: canonicalScope)
    }

    private func baselineAllows(_ scope: IPCPermissionScope, for principal: IPCPrincipal) -> Bool {
        if scope.privilege == .grantApprove, principal.hasApprovalAuthority {
            return true
        }

        guard let boundPaneId = principal.boundPaneId, scope.target == .pane(boundPaneId) else {
            return false
        }

        return Self.baselineSelfPanePrivileges.contains(scope.privilege)
    }

    private static let baselineSelfPanePrivileges: Set<IPCPrivilegeClass> = [
        .eventsRead,
        .paneContextRead,
        .bridgeRead,
        .bridgeContentRead,
        .bridgeControl,
        .bridgeTelemetryRead,
        .bridgeTelemetryFlush,
        .permissionRead,
        .permissionRequest,
        .sessionReportWrite,
        .sessionStateRead,
        .systemRead,
        .terminalInputWrite,
        .terminalSnapshotRead,
        .terminalStatusRead,
        .terminalWait,
    ]

}

extension IPCPrincipal {
    fileprivate var boundPaneId: String? {
        switch kind {
        case .spawnedPaneAgent(let boundPaneId, _):
            boundPaneId
        case .automationClient, .futureMCPClient, .unsafeDebugClient:
            nil
        }
    }

    fileprivate var hasApprovalAuthority: Bool {
        switch approvalAuthority {
        case .delegatedApprover(let scopes), .policyConfigured(let scopes):
            !scopes.isEmpty
        case .noApprovalAuthority:
            false
        }
    }
}
