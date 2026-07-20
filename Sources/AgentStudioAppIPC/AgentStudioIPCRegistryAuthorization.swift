import AgentStudioProgrammaticControl
import Foundation

public struct AppIPCMethodRegistry: Sendable {
    public let definitions: [IPCMethodDefinition]
    private let contributionsByMethodName: [String: AppIPCMethodContribution]

    public init(definitions: [IPCMethodDefinition]) {
        self.definitions = definitions
        self.contributionsByMethodName = [:]
    }

    package init(
        baseDefinitions: [IPCMethodDefinition],
        contributions: [AppIPCMethodContribution]
    ) throws {
        var definitionsByMethodName: [String: IPCMethodDefinition] = [:]
        var mergedDefinitions: [IPCMethodDefinition] = []
        var contributionsByMethodName: [String: AppIPCMethodContribution] = [:]

        for definition in baseDefinitions {
            guard definitionsByMethodName[definition.name] == nil else {
                throw AppIPCMethodRegistryError.duplicateMethodName(definition.name)
            }
            definitionsByMethodName[definition.name] = definition
            mergedDefinitions.append(definition)
        }

        for contribution in contributions {
            let definition = contribution.definition
            try Self.validateContributionDefinition(definition)
            try Self.validateContributionSecurityContract(contribution)
            guard definitionsByMethodName[definition.name] == nil else {
                throw AppIPCMethodRegistryError.duplicateMethodName(definition.name)
            }
            guard contributionsByMethodName[definition.name] == nil else {
                throw AppIPCMethodRegistryError.duplicateMethodName(definition.name)
            }
            definitionsByMethodName[definition.name] = definition
            contributionsByMethodName[definition.name] = contribution
            mergedDefinitions.append(definition)
        }

        self.definitions = mergedDefinitions.sorted { $0.name < $1.name }
        self.contributionsByMethodName = contributionsByMethodName
    }

    public static func phaseOne() throws -> Self {
        let definitions = try [
            Self.method("system.ping", .systemRead, .queryReader, availability: .preAuthentication),
            Self.method("system.identify", .systemRead, .queryReader),
            Self.method("system.version", .systemRead, .queryReader),
            Self.method("system.capabilities", .systemRead, .queryReader),
            Self.method("auth.login", .systemRead, .queryReader, availability: .preAuthentication),
            Self.method("auth.status", .systemRead, .queryReader, availability: .preAuthentication),
            Self.method("window.list", .workspaceRead, .queryReader),
            Self.method("window.current", .workspaceRead, .queryReader),
            Self.method("workspace.list", .workspaceRead, .queryReader),
            Self.method("workspace.current", .workspaceRead, .queryReader),
            Self.method("pane.list", .paneContextRead, .queryReader),
            Self.method("pane.current", .paneContextRead, .queryReader),
            Self.method("pane.focus", .layoutMutate, .workspaceAction),
            Self.method("pane.split", .layoutMutate, .workspaceAction),
            Self.method("pane.close", .layoutMutate, .workspaceAction),
            Self.method("drawer.toggle", .layoutMutate, .workspaceAction),
            Self.method("drawer.addPane", .layoutMutate, .workspaceAction),
            Self.method("terminal.status", .terminalStatusRead, .runtimeCommand),
            Self.method("terminal.send", .terminalInputWrite, .runtimeCommand),
            Self.method("terminal.snapshot", .terminalSnapshotRead, .runtimeCommand),
            Self.method("terminal.wait", .terminalWait, .runtimeCommand, resultSemantics: .accepted),
            Self.method("bridge.diff.load", .layoutMutate, .bridgeCapability),
            Self.method("bridge.fileView.open", .layoutMutate, .bridgeCapability),
            Self.method("bridge.diff.refresh", .bridgeControl, .bridgeCapability),
            Self.method("bridge.diff.getPackage", .bridgeRead, .bridgeCapability),
            Self.method("bridge.diff.renderState", .bridgeRead, .bridgeCapability),
            Self.method("bridge.diff.selectFile", .bridgeControl, .bridgeCapability),
            Self.method("bridge.diff.scrollToFile", .bridgeControl, .bridgeCapability),
            Self.method("bridge.diff.expandFile", .bridgeControl, .bridgeCapability),
            Self.method("bridge.diff.collapseFile", .bridgeControl, .bridgeCapability),
            Self.method("bridge.fileTree.search", .bridgeControl, .bridgeCapability),
            Self.method("bridge.fileTree.setFilter", .bridgeControl, .bridgeCapability),
            Self.method("bridge.fileTree.revealPath", .bridgeControl, .bridgeCapability),
            Self.method("bridge.fileView.getContent", .bridgeContentRead, .bridgeCapability),
            Self.method("bridge.fileView.showMarkdownPreview", .bridgeControl, .bridgeCapability),
            Self.method("bridge.telemetry.snapshot", .bridgeTelemetryRead, .bridgeCapability),
            Self.method("bridge.telemetry.flush", .bridgeTelemetryFlush, .bridgeCapability),
            Self.method("command.list", .systemRead, .queryReader),
            Self.method("command.execute", .appCommandExecute, .appCommand),
            Self.method("ui.commandBar.open", .uiPresent, .uiPresentation),
            Self.method("sidebar.grouping.get", .workspaceRead, .queryReader),
            Self.method("sidebar.surface.get", .workspaceRead, .queryReader),
            Self.method("permission.request", .permissionRequest, .permissionBroker, resultSemantics: .accepted),
            Self.method("permission.requestStatus", .permissionRead, .permissionBroker),
            Self.method("permission.grantStatus", .permissionRead, .permissionBroker),
            Self.method("permission.pendingApprovals", .grantApprove, .permissionBroker),
            Self.method("permission.resolveRequest", .grantApprove, .permissionBroker),
            Self.method("events.subscribe", .eventsRead, .eventReader, resultSemantics: .accepted),
            Self.method("events.unsubscribe", .eventsRead, .eventReader),
        ]

        return Self(definitions: definitions)
    }

    public func definition(named methodName: String) -> IPCMethodDefinition? {
        definitions.first { $0.name == methodName }
    }

    package func contribution(named methodName: String) -> AppIPCMethodContribution? {
        contributionsByMethodName[methodName]
    }

    private static func validateContributionDefinition(_ definition: IPCMethodDefinition) throws {
        guard definition.name.hasPrefix("pane.") else {
            throw AppIPCMethodRegistryError.disallowedContributorNamespace(definition.name)
        }
        guard definition.principalAvailability == .authenticated else {
            throw AppIPCMethodRegistryError.preAuthenticationContributor(definition.name)
        }
        guard definition.executionOwner == .queryReader else {
            throw AppIPCMethodRegistryError.unsupportedContributorExecutionOwner(
                definition.name,
                definition.executionOwner
            )
        }
    }

    private static func validateContributionSecurityContract(_ contribution: AppIPCMethodContribution) throws {
        for privilege in contribution.definition.privilegeClasses {
            let dataScope = PermissionScopeCanonicalizer.dataScope(for: privilege)
            guard contribution.securityContract.dataScopes.contains(dataScope) else {
                throw AppIPCMethodRegistryError.contributionDataScopeOutsideSecurityContract(
                    contribution.definition.name,
                    dataScope
                )
            }
        }
    }

    private static func method(
        _ name: String,
        _ privilege: IPCPrivilegeClass,
        _ owner: IPCExecutionOwner,
        availability: IPCPrincipalAvailability = .authenticated,
        resultSemantics: IPCResultSemantics = .applied
    ) throws -> IPCMethodDefinition {
        try IPCMethodDefinition(
            name: name,
            paramsSchema: IPCSchemaDescription(name: "\(name).params"),
            resultSchema: IPCSchemaDescription(name: "\(name).result"),
            privilegeClasses: [privilege],
            principalAvailability: availability,
            executionOwner: owner,
            resultSemantics: resultSemantics
        )
    }
}

package enum AppIPCMethodRegistryError: Error, Equatable, Sendable {
    case duplicateMethodName(String)
    case disallowedContributorNamespace(String)
    case preAuthenticationContributor(String)
    case contributionDataScopeOutsideSecurityContract(String, IPCDataScope)
    case unsupportedContributorExecutionOwner(String, IPCExecutionOwner)
}

public struct AuthorizationError: Error, Equatable, Sendable {
    public enum Reason: String, Equatable, Sendable {
        case methodNotFound
        case unauthorized
        case noBoundPane
    }

    public let reason: Reason

    public init(reason: Reason) {
        self.reason = reason
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
            privilege: scope.privilege, target: target, dataScope: Self.dataScope(for: scope.privilege))
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
        case .debugUnsafe:
            .unspecified
        }
    }
}

public struct AuthorizationService: Sendable {
    private let methodRegistry: AppIPCMethodRegistry
    private let grantLedger: GrantLedger
    private let canonicalizer: PermissionScopeCanonicalizer

    public init(
        methodRegistry: AppIPCMethodRegistry,
        grantLedger: GrantLedger,
        canonicalizer: PermissionScopeCanonicalizer
    ) {
        self.methodRegistry = methodRegistry
        self.grantLedger = grantLedger
        self.canonicalizer = canonicalizer
    }

    public func authorize(
        principal: IPCPrincipal,
        methodName: String,
        requestedTarget: IPCTargetScope,
        activePaneId _: String?
    ) throws {
        guard let definition = methodRegistry.definition(named: methodName) else {
            throw AuthorizationError(reason: .methodNotFound)
        }

        if Self.authenticatedAutomationMethodAllowlist.contains(methodName), methodName != "command.execute" {
            guard isAuthenticatedAutomation(principal) else {
                throw AuthorizationError(reason: .unauthorized)
            }
        }

        if unsafeDebugAllows(methodName: methodName, definition: definition, for: principal) {
            return
        }

        for privilege in definition.privilegeClasses {
            let requestedScope = IPCPermissionScope(
                privilege: privilege,
                target: requestedTarget,
                dataScope: PermissionScopeCanonicalizer.dataScope(for: privilege)
            )
            let canonicalScope = try canonicalizer.canonicalize(requestedScope, for: principal)

            if baselineAllows(canonicalScope, for: principal) {
                continue
            }

            if canonicalScope.privilege == .debugUnsafe {
                throw AuthorizationError(reason: .unauthorized)
            }

            if grantLedger.contains(canonicalScope, for: principal.principalId) {
                continue
            }

            throw AuthorizationError(reason: .unauthorized)
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

        throw AuthorizationError(reason: .unauthorized)
    }

    private func unsafeDebugAllows(
        methodName: String,
        definition: IPCMethodDefinition,
        for principal: IPCPrincipal
    ) -> Bool {
        guard principal.accessMode == .unsafeDebug else {
            return false
        }

        switch principal.kind {
        case .unsafeDebugClient, .automationClient:
            break
        case .spawnedPaneAgent, .futureMCPClient:
            return false
        }

        guard Self.unsafeDebugMethodAllowlist.contains(methodName) else {
            return false
        }

        return !definition.privilegeClasses.contains(.grantApprove)
            && !definition.privilegeClasses.contains(.permissionRequest)
            && !definition.privilegeClasses.contains(.permissionRead)
            && !definition.privilegeClasses.contains(.eventsRead)
    }

    private func isAuthenticatedAutomation(_ principal: IPCPrincipal) -> Bool {
        guard principal.accessMode == .unsafeDebug else {
            return false
        }
        guard case .automationClient = principal.kind else {
            return false
        }
        return true
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
        .systemRead,
        .terminalInputWrite,
        .terminalSnapshotRead,
        .terminalStatusRead,
        .terminalWait,
    ]

    private static let unsafeDebugMethodAllowlist: Set<String> = [
        "system.identify",
        "system.version",
        "system.capabilities",
        "window.list",
        "window.current",
        "workspace.list",
        "workspace.current",
        "pane.list",
        "pane.current",
        "pane.focus",
        "pane.split",
        "pane.close",
        "pane.snapshot",
        "drawer.toggle",
        "drawer.addPane",
        "terminal.status",
        "terminal.send",
        "terminal.snapshot",
        "terminal.wait",
        "bridge.diff.load",
        "bridge.fileView.open",
        "bridge.diff.refresh",
        "bridge.diff.getPackage",
        "bridge.diff.renderState",
        "bridge.diff.selectFile",
        "bridge.diff.scrollToFile",
        "bridge.diff.expandFile",
        "bridge.diff.collapseFile",
        "bridge.fileTree.search",
        "bridge.fileTree.setFilter",
        "bridge.fileTree.revealPath",
        "bridge.fileView.getContent",
        "bridge.fileView.showMarkdownPreview",
        "bridge.telemetry.snapshot",
        "bridge.telemetry.flush",
        "command.list",
        "ui.commandBar.open",
    ]

    private static let authenticatedAutomationMethodAllowlist: Set<String> = [
        "command.execute",
        "sidebar.grouping.get",
        "sidebar.surface.get",
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
