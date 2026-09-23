import AgentStudioProgrammaticControl
import Foundation

extension AppIPCBuiltInMethodRegistrations {
    static func layoutAndTerminalRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        let layout = try layoutRegistrations(inputs: inputs)
        let terminal = try terminalRegistrations(inputs: inputs)
        return layout + terminal
    }

    private static func layoutRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        try paneLayoutRegistrations(inputs: inputs)
            + drawerLayoutRegistrations(inputs: inputs)
    }

    private static func paneLayoutRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        let descriptors = inputs.catalog.layout
        return try [
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.paneFocus,
                correlation: .required(\.correlationId),
                resolveTarget: { parameters, _, tools in
                    try await AppIPCBuiltInRegistrationSupport.canonicalPaneTarget(
                        parameters,
                        rawHandle: parameters.handle,
                        tools: tools,
                        replacingHandle: { original, canonicalHandle in
                            IPCPaneControlParams(
                                handle: canonicalHandle,
                                correlationId: original.correlationId
                            )
                        }
                    )
                },
                connectionHandler: { parameters, _, _ in
                    try await inputs.ports.layoutPort.focusPane(IPCHandle.parse(parameters.handle))
                }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.paneSplit,
                correlation: .required {
                    try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId)
                },
                resolveTarget: { parameters, _, tools in
                    try await AppIPCBuiltInRegistrationSupport.canonicalPaneTarget(
                        parameters,
                        rawHandle: parameters.handle,
                        tools: tools,
                        replacingHandle: { original, canonicalHandle in
                            IPCPaneSplitParams(
                                handle: canonicalHandle,
                                direction: original.direction,
                                correlationId: original.correlationId
                            )
                        }
                    )
                },
                connectionHandler: { parameters, _, _ in
                    try await inputs.ports.layoutPort.splitPane(parameters)
                }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.paneClose,
                correlation: .required {
                    try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId)
                },
                resolveTarget: { parameters, _, tools in
                    try await AppIPCBuiltInRegistrationSupport.canonicalPaneTarget(
                        parameters,
                        rawHandle: parameters.handle,
                        tools: tools,
                        agentArgumentRule: { .closesPane($0) },
                        replacingHandle: { original, canonicalHandle in
                            IPCPaneCloseParams(
                                handle: canonicalHandle,
                                correlationId: original.correlationId
                            )
                        }
                    )
                },
                connectionHandler: { parameters, _, _ in
                    try await inputs.ports.layoutPort.closePane(parameters)
                }
            ).erase(),
        ]
    }

    private static func drawerLayoutRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        let descriptors = inputs.catalog.layout
        return try [
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.drawerToggle,
                correlation: .required {
                    try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId)
                },
                resolveTarget: { parameters, _, tools in
                    try await AppIPCBuiltInRegistrationSupport.canonicalPaneTarget(
                        parameters,
                        rawHandle: parameters.parentPaneHandle,
                        tools: tools,
                        replacingHandle: { original, canonicalHandle in
                            IPCDrawerToggleParams(
                                parentPaneHandle: canonicalHandle,
                                correlationId: original.correlationId
                            )
                        }
                    )
                },
                connectionHandler: { parameters, _, _ in
                    try await inputs.ports.layoutPort.toggleDrawer(parameters)
                }
            ).erase(),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.drawerAddPane,
                correlation: .required {
                    try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId)
                },
                resolveTarget: { parameters, _, tools in
                    try await AppIPCBuiltInRegistrationSupport.canonicalPaneTarget(
                        parameters,
                        rawHandle: parameters.parentPaneHandle,
                        tools: tools,
                        agentArgumentRule: { .addsDrawerChild(parentPaneId: $0) },
                        replacingHandle: { original, canonicalHandle in
                            IPCDrawerAddPaneParams(
                                parentPaneHandle: canonicalHandle,
                                correlationId: original.correlationId
                            )
                        }
                    )
                },
                connectionHandler: { parameters, _, _ in
                    try await inputs.ports.layoutPort.addDrawerPane(parameters)
                }
            ).erase(),
        ]
    }

    private static func terminalRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        let descriptors = inputs.catalog.terminal
        return try [
            terminalPaneReadRegistration(
                descriptor: descriptors.terminalStatus,
                handler: { handle in try await inputs.ports.runtimePort.terminalStatus(handle) }
            ),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.terminalSend,
                correlation: .required(\.correlationId),
                resolveTarget: { parameters, _, tools in
                    try await AppIPCBuiltInRegistrationSupport.canonicalPaneTarget(
                        parameters,
                        rawHandle: parameters.handle,
                        tools: tools,
                        replacingHandle: { original, canonicalHandle in
                            IPCTerminalSendParams(
                                handle: canonicalHandle,
                                input: original.input,
                                correlationId: original.correlationId
                            )
                        }
                    )
                },
                connectionHandler: { parameters, _, _ in
                    try await inputs.ports.runtimePort.sendTerminalInput(
                        to: IPCHandle.parse(parameters.handle),
                        input: parameters.input,
                        correlationId: parameters.correlationId
                    )
                }
            ).erase(),
            terminalPaneReadRegistration(
                descriptor: descriptors.terminalSnapshot,
                handler: { handle in try await inputs.ports.runtimePort.terminalSnapshot(handle) }
            ),
            AppIPCTypedMethodRegistration(
                descriptor: descriptors.terminalWait,
                correlation: .notRequired,
                resolveTarget: { parameters, _, tools in
                    try await AppIPCBuiltInRegistrationSupport.canonicalPaneTarget(
                        parameters,
                        rawHandle: parameters.handle,
                        tools: tools,
                        replacingHandle: { original, canonicalHandle in
                            IPCTerminalWaitParams(
                                handle: canonicalHandle,
                                condition: original.condition,
                                timeoutSeconds: original.timeoutSeconds,
                                afterSequence: original.afterSequence
                            )
                        }
                    )
                },
                connectionHandler: { parameters, _, _ in
                    try await inputs.ports.runtimePort.waitForTerminal(
                        IPCHandle.parse(parameters.handle),
                        condition: parameters.condition,
                        timeout: AppIPCBuiltInRegistrationSupport.duration(seconds: parameters.timeoutSeconds),
                        afterSequence: parameters.afterSequence
                    )
                }
            ).erase(),
        ]
    }

    private static func terminalPaneReadRegistration<Result>(
        descriptor: IPCMethodDescriptor<IPCPaneSelectorParams, Result>,
        handler: @escaping @Sendable (IPCHandle) async throws -> Result
    ) throws -> AnyAppIPCMethodRegistration
    where Result: Codable & Sendable {
        try AppIPCTypedMethodRegistration(
            descriptor: descriptor,
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
            connectionHandler: { parameters, _, _ in
                try await handler(IPCHandle.parse(parameters.handle))
            }
        ).erase()
    }
}
