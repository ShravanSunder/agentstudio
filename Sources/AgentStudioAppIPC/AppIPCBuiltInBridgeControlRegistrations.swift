import AgentStudioProgrammaticControl
import Foundation

struct AppIPCBridgePageControlBinding<Parameters>: Sendable
where Parameters: Codable & Sendable {
    let descriptor: IPCMethodDescriptor<Parameters, IPCBridgePageControlResult>
    let correlation: @Sendable (Parameters) throws -> UUID
    let rawHandle: @Sendable (Parameters) -> String
    let rebuild: @Sendable (Parameters, String) -> Parameters
    let handler: @Sendable (Parameters) async throws -> IPCBridgePageControlResult
    let publishesSelection: Bool
}

extension AppIPCBuiltInMethodRegistrations {
    static func bridgeControlAndTelemetryRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        try bridgeReviewControlRegistrations(inputs: inputs)
            + bridgeRemainingPageControlRegistrations(inputs: inputs)
            + bridgeContentAndTelemetryRegistrations(inputs: inputs)
            + [bridgeFilesSearchRegistration(inputs: inputs)]
    }

    private static func bridgeFilesSearchRegistration(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> AnyAppIPCMethodRegistration {
        try bridgePaneRegistration(
            binding: AppIPCBridgePaneBinding(
                descriptor: inputs.catalog.bridge.control.bridgeFilesSearch,
                correlation: nil,
                rawHandle: { $0.handle },
                rebuild: { original, canonicalHandle in
                    IPCBridgeFilesSearchParams(
                        handle: canonicalHandle,
                        searchText: original.searchText,
                        searchMode: original.searchMode,
                        scope: original.scope,
                        worktreeId: original.worktreeId,
                        limit: original.limit
                    )
                },
                handler: { parameters in try await inputs.ports.bridgePort.searchFiles(parameters) }
            ),
            inputs: inputs
        )
    }

    private static func bridgeReviewControlRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        let control = inputs.catalog.bridge.control
        return try [
            bridgePageControlRegistration(
                binding: AppIPCBridgePageControlBinding(
                    descriptor: control.bridgeDiffScrollToFile,
                    correlation: { try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId) },
                    rawHandle: { $0.handle },
                    rebuild: { original, canonicalHandle in
                        IPCBridgeDiffScrollToFileParams(
                            handle: canonicalHandle,
                            itemId: original.itemId,
                            correlationId: original.correlationId
                        )
                    },
                    handler: { try await inputs.ports.bridgePort.scrollToFile($0) },
                    publishesSelection: true
                ),
                inputs: inputs
            )
        ]
    }

    private static func bridgeRemainingPageControlRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        let control = inputs.catalog.bridge.control
        return try [
            bridgePageControlRegistration(
                binding: AppIPCBridgePageControlBinding(
                    descriptor: control.bridgeDiffExpandFile,
                    correlation: { try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId) },
                    rawHandle: { $0.handle },
                    rebuild: { original, canonicalHandle in
                        IPCBridgeDiffExpandFileParams(
                            handle: canonicalHandle,
                            itemId: original.itemId,
                            correlationId: original.correlationId
                        )
                    },
                    handler: { try await inputs.ports.bridgePort.expandFile($0) },
                    publishesSelection: false
                ),
                inputs: inputs
            ),
            bridgePageControlRegistration(
                binding: AppIPCBridgePageControlBinding(
                    descriptor: control.bridgeDiffCollapseFile,
                    correlation: { try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId) },
                    rawHandle: { $0.handle },
                    rebuild: { original, canonicalHandle in
                        IPCBridgeDiffCollapseFileParams(
                            handle: canonicalHandle,
                            itemId: original.itemId,
                            correlationId: original.correlationId
                        )
                    },
                    handler: { try await inputs.ports.bridgePort.collapseFile($0) },
                    publishesSelection: false
                ),
                inputs: inputs
            ),
            bridgePageControlRegistration(
                binding: AppIPCBridgePageControlBinding(
                    descriptor: control.bridgeFileTreeSearch,
                    correlation: { try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId) },
                    rawHandle: { $0.handle },
                    rebuild: { original, canonicalHandle in
                        IPCBridgeFileTreeSearchParams(
                            handle: canonicalHandle,
                            searchText: original.searchText,
                            searchMode: original.searchMode,
                            correlationId: original.correlationId
                        )
                    },
                    handler: { try await inputs.ports.bridgePort.searchFileTree($0) },
                    publishesSelection: false
                ),
                inputs: inputs
            ),
            bridgePageControlRegistration(
                binding: AppIPCBridgePageControlBinding(
                    descriptor: control.bridgeFileTreeSetFilter,
                    correlation: { try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId) },
                    rawHandle: { $0.handle },
                    rebuild: { original, canonicalHandle in
                        IPCBridgeFileTreeSetFilterParams(
                            handle: canonicalHandle,
                            candidate: original.candidate,
                            correlationId: original.correlationId
                        )
                    },
                    handler: { try await inputs.ports.bridgePort.setFileTreeFilter($0) },
                    publishesSelection: false
                ),
                inputs: inputs
            ),
            bridgePageControlRegistration(
                binding: AppIPCBridgePageControlBinding(
                    descriptor: control.bridgeFileTreeRevealPath,
                    correlation: { try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId) },
                    rawHandle: { $0.handle },
                    rebuild: { original, canonicalHandle in
                        IPCBridgeFileTreeRevealPathParams(
                            handle: canonicalHandle,
                            path: original.path,
                            correlationId: original.correlationId
                        )
                    },
                    handler: { try await inputs.ports.bridgePort.revealFileTreePath($0) },
                    publishesSelection: true
                ),
                inputs: inputs
            ),
        ]
    }

    private static func bridgeContentAndTelemetryRegistrations(
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> [AnyAppIPCMethodRegistration] {
        let control = inputs.catalog.bridge.control
        let telemetry = inputs.catalog.bridge.telemetry
        return try [
            bridgePaneRegistration(
                binding: AppIPCBridgePaneBinding(
                    descriptor: control.bridgeFileViewGetContent,
                    correlation: nil,
                    rawHandle: { $0.handle },
                    rebuild: { original, canonicalHandle in
                        IPCBridgeContentGetParams(
                            handle: canonicalHandle,
                            contentHandleId: original.contentHandleId,
                            reviewGeneration: original.reviewGeneration
                        )
                    },
                    handler: { parameters in
                        let result = try await inputs.ports.bridgePort.getContent(parameters)
                        await publishBridgeEvent(
                            name: .bridgeContentReady,
                            payload: IPCBridgeEventPayload(
                                paneId: result.paneId,
                                itemId: result.handle.itemId,
                                contentHandleId: result.handle.handleId
                            ),
                            inputs: inputs
                        )
                        return result
                    }
                ),
                inputs: inputs,
            ),
            bridgePageControlRegistration(
                binding: AppIPCBridgePageControlBinding(
                    descriptor: control.bridgeFileViewShowMarkdownPreview,
                    correlation: { try AppIPCBuiltInRegistrationSupport.requiredCorrelation($0.correlationId) },
                    rawHandle: { $0.handle },
                    rebuild: { original, canonicalHandle in
                        IPCBridgeFileViewShowMarkdownPreviewParams(
                            handle: canonicalHandle,
                            itemId: original.itemId,
                            correlationId: original.correlationId
                        )
                    },
                    handler: { try await inputs.ports.bridgePort.showMarkdownPreview($0) },
                    publishesSelection: false
                ),
                inputs: inputs
            ),
            bridgePaneRegistration(
                binding: AppIPCBridgePaneBinding(
                    descriptor: telemetry.bridgeTelemetrySnapshot,
                    correlation: nil,
                    rawHandle: { $0.handle },
                    rebuild: { _, canonicalHandle in IPCBridgePaneParams(handle: canonicalHandle) },
                    handler: { parameters in
                        try await inputs.ports.bridgePort.telemetrySnapshot(IPCHandle.parse(parameters.handle))
                    }
                ),
                inputs: inputs,
            ),
            bridgePaneRegistration(
                binding: AppIPCBridgePaneBinding(
                    descriptor: telemetry.bridgeTelemetryFlush,
                    correlation: { $0.correlationId },
                    rawHandle: { $0.handle },
                    rebuild: { original, canonicalHandle in
                        IPCBridgeTelemetryFlushParams(
                            handle: canonicalHandle,
                            correlationId: original.correlationId
                        )
                    },
                    handler: { parameters in
                        let result = try await inputs.ports.bridgePort.flushTelemetry(
                            IPCHandle.parse(parameters.handle)
                        )
                        await publishBridgeEvent(
                            name: .bridgeTelemetrySampled,
                            payload: IPCBridgeEventPayload(paneId: result.paneId),
                            inputs: inputs
                        )
                        return result
                    }
                ),
                inputs: inputs,
            ),
        ]
    }

    private static func bridgePageControlRegistration<Parameters>(
        binding: AppIPCBridgePageControlBinding<Parameters>,
        inputs: AppIPCBuiltInRegistrationInputs
    ) throws -> AnyAppIPCMethodRegistration
    where Parameters: Codable & Sendable {
        try bridgePaneRegistration(
            binding: AppIPCBridgePaneBinding(
                descriptor: binding.descriptor,
                correlation: binding.correlation,
                rawHandle: binding.rawHandle,
                rebuild: binding.rebuild,
                handler: { parameters in
                    let result = try await binding.handler(parameters)
                    if binding.publishesSelection,
                        result.status == "accepted",
                        let itemId = result.itemId
                    {
                        await publishBridgeFileSelected(
                            paneId: result.paneId,
                            itemId: itemId,
                            correlationId: result.correlationId,
                            inputs: inputs
                        )
                    }
                    return result
                }
            ),
            inputs: inputs
        )
    }
}
