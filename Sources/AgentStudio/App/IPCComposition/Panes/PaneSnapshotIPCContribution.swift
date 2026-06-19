import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioProgrammaticControl
import Foundation

struct AgentStudioIPCContributionComposition {
    let baseDefinitions: [IPCMethodDefinition]
    let methodContributions: [AppIPCMethodContribution]
    let methodRegistry: AppIPCMethodRegistry
}

enum AgentStudioIPCContributionRegistry {
    static func phaseARegistry() throws -> AppIPCMethodRegistry {
        try phaseAComposition().methodRegistry
    }

    static func phaseAComposition() throws -> AgentStudioIPCContributionComposition {
        let baseRegistry = try AppIPCMethodRegistry.phaseOne()
        let methodContributions = [try paneSnapshotContribution()]
        let methodRegistry = try AppIPCMethodRegistry(
            baseDefinitions: baseRegistry.definitions,
            contributions: methodContributions
        )
        return AgentStudioIPCContributionComposition(
            baseDefinitions: baseRegistry.definitions,
            methodContributions: methodContributions,
            methodRegistry: methodRegistry
        )
    }

    private static func paneSnapshotContribution() throws -> AppIPCMethodContribution {
        try AppIPCMethodContribution(
            definition: IPCMethodDefinition(
                name: "pane.snapshot",
                paramsSchema: IPCSchemaDescription(name: "pane.snapshot.params"),
                resultSchema: IPCSchemaDescription(name: "pane.snapshot.result"),
                privilegeClasses: [.paneContextRead],
                executionOwner: .queryReader,
                resultSemantics: .applied
            ),
            securityContract: AppIPCContributionSecurityContract(
                targetVocabulary: [.pane],
                dataScopes: [.paneContext],
                sensitiveDataExclusions: [
                    "cwd",
                    "paneTitle",
                    "rawTerminalOutput",
                    "rawRuntimePayload",
                    "tabTitle",
                    "url",
                    "zmxSessionIdentifier",
                ]
            ),
            authorizationContext: { request, _, tools in
                let params = try decodePaneSnapshotParams(from: request.params)
                let canonicalHandle = try await tools.canonicalizePaneHandle(params.handle)
                guard case .canonicalUUID(let paneId) = canonicalHandle.reference else {
                    throw AppIPCQueryError(reason: .targetNotFound)
                }
                return try AppIPCAuthorizedRequestContext(
                    request: request.replacingHandle(canonicalHandle.rawIPCHandleString),
                    target: .pane(paneId.uuidString)
                )
            },
            dispatch: { request, _, context in
                let params = try decodePaneSnapshotParams(from: request.params)
                let paneId = try context.uuidFromPaneHandle(params.handle)
                let snapshot = try await context.snapshotPane(paneId)
                return try JSONRPCCodec.encodeJSONValue(snapshot)
            }
        )
    }
}

private struct PaneSnapshotContributionParams: Decodable {
    let handle: String
}

private func decodePaneSnapshotParams(from params: JSONValue?) throws -> PaneSnapshotContributionParams {
    let value = params ?? .object([:])
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(PaneSnapshotContributionParams.self, from: data)
}
