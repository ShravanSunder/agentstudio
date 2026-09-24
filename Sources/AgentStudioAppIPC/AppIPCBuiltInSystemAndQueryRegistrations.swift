import AgentStudioProgrammaticControl
import Foundation

extension AppIPCBuiltInMethodRegistrations {
    static func systemAndQueryRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        try systemAndAuthRegistrations(inputs: inputs)
            + workspaceQueryRegistrations(inputs: inputs)
    }

    private static func systemAndAuthRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        let descriptors = inputs.catalog
        return try [
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.systemAndAuth.systemPing,
                correlation: .notRequired,
                resolveTarget: { parameters, _, _ in
                    AppIPCBuiltInRegistrationSupport.appTarget(parameters)
                },
                connectionHandler: { _, _, _ in
                    IPCSystemPingResult(runtimeId: inputs.runtimeId)
                }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.systemAndAuth.systemIdentify,
                correlation: .notRequired,
                resolveTarget: { parameters, context, _ in
                    try AppIPCBuiltInRegistrationSupport.principalTarget(parameters, context: context)
                },
                connectionHandler: { _, _, _ in
                    try await inputs.ports.queryPort.systemIdentify()
                }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.systemAndAuth.systemVersion,
                correlation: .notRequired,
                resolveTarget: { parameters, context, _ in
                    try AppIPCBuiltInRegistrationSupport.principalTarget(parameters, context: context)
                },
                connectionHandler: { _, _, _ in
                    try await inputs.ports.queryPort.systemVersion()
                }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.systemAndAuth.authLogin,
                correlation: .notRequired,
                resolveTarget: { parameters, _, _ in
                    AppIPCBuiltInRegistrationSupport.appTarget(parameters)
                },
                connectionHandler: { parameters, context, _ in
                    try await context.authenticate(parameters)
                }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.systemAndAuth.authStatus,
                correlation: .notRequired,
                resolveTarget: { parameters, _, _ in
                    AppIPCBuiltInRegistrationSupport.appTarget(parameters)
                },
                connectionHandler: { _, context, _ in
                    context.authenticationStatus()
                }
            ).erase(),
        ]
    }

    private static func workspaceQueryRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        let descriptors = inputs.catalog
        return try [
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.workspaceQueries.windowList,
                correlation: .notRequired,
                resolveTarget: { parameters, _, _ in AppIPCBuiltInRegistrationSupport.appTarget(parameters) },
                connectionHandler: { _, _, _ in try await inputs.ports.queryPort.listWindows() }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.workspaceQueries.windowCurrent,
                correlation: .notRequired,
                resolveTarget: { parameters, _, _ in AppIPCBuiltInRegistrationSupport.appTarget(parameters) },
                connectionHandler: { _, _, _ in try await inputs.ports.queryPort.currentWindow() }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.workspaceQueries.workspaceList,
                correlation: .notRequired,
                resolveTarget: { parameters, _, _ in AppIPCBuiltInRegistrationSupport.appTarget(parameters) },
                connectionHandler: { _, _, _ in try await inputs.ports.queryPort.listWorkspaces() }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.workspaceQueries.workspaceCurrent,
                correlation: .notRequired,
                resolveTarget: { parameters, _, _ in AppIPCBuiltInRegistrationSupport.appTarget(parameters) },
                connectionHandler: { _, _, _ in try await inputs.ports.queryPort.currentWorkspace() }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.workspaceQueries.paneList,
                correlation: .notRequired,
                resolveTarget: { parameters, _, _ in AppIPCBuiltInRegistrationSupport.appTarget(parameters) },
                connectionHandler: { _, _, _ in try await inputs.ports.queryPort.listPanes() }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.workspaceQueries.paneCurrent,
                correlation: .notRequired,
                resolveTarget: { parameters, _, _ in AppIPCBuiltInRegistrationSupport.appTarget(parameters) },
                connectionHandler: { _, _, _ in try await inputs.ports.queryPort.currentPane() }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.workspaceQueries.paneSnapshot,
                correlation: .notRequired,
                resolveTarget: { parameters, _, tools in
                    try await AppIPCBuiltInRegistrationSupport.canonicalPaneTarget(
                        parameters,
                        rawHandle: parameters.handle,
                        tools: tools,
                        replacingHandle: { _, canonicalHandle in
                            IPCPaneSelectorParams(handle: canonicalHandle)
                        }
                    )
                },
                connectionHandler: { parameters, context, _ in
                    let handle = try IPCHandle.parse(parameters.handle)
                    guard case (.pane, .canonicalUUID(let paneId)) = (handle.kind, handle.reference) else {
                        throw AppIPCTypedMethodRegistrationError.targetKindNotAllowed
                    }
                    return try await inputs.ports.queryPort.snapshotPane(
                        paneId, ownPaneAssertion: AppIPCOwnPaneAssertion(principal: context.principal))
                }
            ).erase(),
        ]
    }
}
