import AgentStudioAppIPC
import AgentStudioProgrammaticControl

func badIPCContributionLocation() throws -> AppIPCMethodContribution {
    try AppIPCMethodContribution(
        definition: IPCMethodDefinition(
            name: "pane.badLocation",
            paramsSchema: IPCSchemaDescription(name: "pane.badLocation.params"),
            resultSchema: IPCSchemaDescription(name: "pane.badLocation.result"),
            privilegeClasses: [.paneContextRead],
            executionOwner: .queryReader,
            resultSemantics: .applied
        ),
        securityContract: AppIPCContributionSecurityContract(
            targetVocabulary: [.pane],
            dataScopes: [.paneContext],
            sensitiveDataExclusions: ["cwd"]
        ),
        authorizationContext: { request, _, _ in
            AppIPCAuthorizedRequestContext(request: request, target: .pane("test-pane"))
        },
        dispatch: { _, _, _ in
            .object([:])
        }
    )
}
