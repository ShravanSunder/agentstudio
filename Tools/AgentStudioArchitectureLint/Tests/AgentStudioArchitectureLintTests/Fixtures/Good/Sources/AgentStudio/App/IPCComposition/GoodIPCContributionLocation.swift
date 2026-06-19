import AgentStudioAppIPC
import AgentStudioProgrammaticControl

func goodIPCContributionLocation() throws -> AppIPCMethodContribution {
    try AppIPCMethodContribution(
        definition: IPCMethodDefinition(
            name: "pane.goodLocation",
            paramsSchema: IPCSchemaDescription(name: "pane.goodLocation.params"),
            resultSchema: IPCSchemaDescription(name: "pane.goodLocation.result"),
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
