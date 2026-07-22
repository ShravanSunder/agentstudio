import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

package enum AppIPCContributionTargetVocabulary: String, Hashable, Sendable {
    case app
    case pane
    case selfPane
    case workspace
}

package enum AppIPCMethodContributionError: Error, Equatable, Sendable {
    case emptyTargetVocabulary
    case emptyDataScopes
    case missingSensitiveDataExclusions
}

package enum AppIPCContributionRequestError: Error, Equatable, Sendable {
    case invalidParams
    case targetOutsideSecurityContract
}

package enum AppIPCContributionParameters {
    package static func decode<T: Decodable>(_ type: T.Type, from params: JSONValue?) throws -> T {
        let value = params ?? .object([:])
        do {
            let data = try JSONEncoder().encode(value)
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw AppIPCContributionRequestError.invalidParams
        }
    }
}

package struct AppIPCContributionSecurityContract: Equatable, Sendable {
    package let targetVocabulary: Set<AppIPCContributionTargetVocabulary>
    package let dataScopes: Set<IPCDataScope>
    package let sensitiveDataExclusions: Set<String>

    package init(
        targetVocabulary: Set<AppIPCContributionTargetVocabulary>,
        dataScopes: Set<IPCDataScope>,
        sensitiveDataExclusions: Set<String>
    ) throws {
        guard !targetVocabulary.isEmpty else {
            throw AppIPCMethodContributionError.emptyTargetVocabulary
        }
        guard !dataScopes.isEmpty else {
            throw AppIPCMethodContributionError.emptyDataScopes
        }
        guard !sensitiveDataExclusions.isEmpty else {
            throw AppIPCMethodContributionError.missingSensitiveDataExclusions
        }

        self.targetVocabulary = targetVocabulary
        self.dataScopes = dataScopes
        self.sensitiveDataExclusions = sensitiveDataExclusions
    }

    package func allowsTarget(_ target: IPCTargetScope) -> Bool {
        switch target {
        case .app:
            targetVocabulary.contains(.app)
        case .pane:
            targetVocabulary.contains(.pane)
        case .selfPane:
            targetVocabulary.contains(.selfPane)
        case .workspace:
            targetVocabulary.contains(.workspace)
        }
    }
}

package struct AppIPCAuthorizedRequestContext: Sendable {
    package let request: JSONRPCRequest
    package let target: IPCTargetScope

    package init(request: JSONRPCRequest, target: IPCTargetScope) {
        self.request = request
        self.target = target
    }
}

package struct AppIPCContributionAuthorizationTools: Sendable {
    private let paneHandleCanonicalizer: @Sendable (String) async throws -> IPCHandle

    package init(paneHandleCanonicalizer: @escaping @Sendable (String) async throws -> IPCHandle) {
        self.paneHandleCanonicalizer = paneHandleCanonicalizer
    }

    package func canonicalizePaneHandle(_ rawHandle: String) async throws -> IPCHandle {
        try await paneHandleCanonicalizer(rawHandle)
    }
}

package struct AppIPCContributionDispatchContext: Sendable {
    private let authorizedTarget: IPCTargetScope
    private let principal: IPCPrincipal
    private let paneSnapshotReader: @Sendable (UUID) async throws -> IPCPaneSnapshotResult
    private let paneHandleDecoder: @Sendable (String) throws -> UUID

    package init(
        authorizedTarget: IPCTargetScope,
        principal: IPCPrincipal,
        paneSnapshotReader: @escaping @Sendable (UUID) async throws -> IPCPaneSnapshotResult,
        paneHandleDecoder: @escaping @Sendable (String) throws -> UUID
    ) {
        self.authorizedTarget = authorizedTarget
        self.principal = principal
        self.paneSnapshotReader = paneSnapshotReader
        self.paneHandleDecoder = paneHandleDecoder
    }

    package func uuidFromPaneHandle(_ rawHandle: String) throws -> UUID {
        let paneId = try paneHandleDecoder(rawHandle)
        try validateAuthorizedPaneId(paneId)
        return paneId
    }

    package func snapshotPane(_ paneId: UUID) async throws -> IPCPaneSnapshotResult {
        try validateAuthorizedPaneId(paneId)
        return try await paneSnapshotReader(paneId)
    }

    private func validateAuthorizedPaneId(_ paneId: UUID) throws {
        guard allowsPaneId(paneId) else {
            throw AppIPCContributionRequestError.targetOutsideSecurityContract
        }
    }

    private func allowsPaneId(_ paneId: UUID) -> Bool {
        switch authorizedTarget {
        case .pane(let rawPaneId):
            paneIdMatches(paneId, rawPaneId: rawPaneId)
        case .selfPane:
            principalBoundPaneMatches(paneId)
        case .app, .workspace:
            false
        }
    }

    private func principalBoundPaneMatches(_ paneId: UUID) -> Bool {
        switch principal.kind {
        case .spawnedPaneAgent(let boundPaneId, _):
            paneIdMatches(paneId, rawPaneId: boundPaneId)
        case .automationClient, .futureMCPClient, .unsafeDebugClient:
            false
        }
    }

    private func paneIdMatches(_ paneId: UUID, rawPaneId: String) -> Bool {
        UUID(uuidString: rawPaneId) == paneId || rawPaneId == paneId.uuidString
    }
}

package struct AppIPCMethodContribution: Sendable {
    package let definition: IPCMethodDefinition
    package let securityContract: AppIPCContributionSecurityContract
    package let authorizationContext:
        @Sendable (JSONRPCRequest, IPCPrincipal, AppIPCContributionAuthorizationTools) async throws ->
            AppIPCAuthorizedRequestContext
    package let dispatch:
        @Sendable (JSONRPCRequest, IPCPrincipal, AppIPCContributionDispatchContext) async throws -> JSONValue?

    package init(
        definition: IPCMethodDefinition,
        securityContract: AppIPCContributionSecurityContract,
        authorizationContext:
            @escaping @Sendable (
                JSONRPCRequest,
                IPCPrincipal,
                AppIPCContributionAuthorizationTools
            ) async throws -> AppIPCAuthorizedRequestContext,
        dispatch:
            @escaping @Sendable (
                JSONRPCRequest,
                IPCPrincipal,
                AppIPCContributionDispatchContext
            ) async throws -> JSONValue?
    ) {
        self.definition = definition
        self.securityContract = securityContract
        self.authorizationContext = authorizationContext
        self.dispatch = dispatch
    }
}
