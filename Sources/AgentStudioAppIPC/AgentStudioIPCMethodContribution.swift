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
    private let paneSnapshotReader: @Sendable (UUID) async throws -> IPCPaneSnapshotResult
    private let paneHandleDecoder: @Sendable (String) throws -> UUID

    package init(
        paneSnapshotReader: @escaping @Sendable (UUID) async throws -> IPCPaneSnapshotResult,
        paneHandleDecoder: @escaping @Sendable (String) throws -> UUID
    ) {
        self.paneSnapshotReader = paneSnapshotReader
        self.paneHandleDecoder = paneHandleDecoder
    }

    package func uuidFromPaneHandle(_ rawHandle: String) throws -> UUID {
        try paneHandleDecoder(rawHandle)
    }

    package func snapshotPane(_ paneId: UUID) async throws -> IPCPaneSnapshotResult {
        try await paneSnapshotReader(paneId)
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
