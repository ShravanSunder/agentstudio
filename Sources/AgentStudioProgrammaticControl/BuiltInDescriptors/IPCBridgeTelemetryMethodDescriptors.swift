import Foundation

package struct IPCBridgeTelemetryMethodDescriptors: Sendable {
    package let bridgeTelemetrySnapshot: IPCMethodDescriptor<IPCBridgePaneParams, IPCBridgeTelemetrySnapshotResult>
    package let bridgeTelemetryFlush: IPCMethodDescriptor<IPCBridgeTelemetryFlushParams, IPCBridgeTelemetryFlushResult>

    init(examples: IPCBuiltInMethodExampleContext) throws {
        bridgeTelemetrySnapshot = try IPCBuiltInDescriptorSupport.read(
            name: "bridge.telemetry.snapshot",
            description: "Read the current telemetry report or its unavailable reason.",
            parameters: IPCBridgePaneParams(handle: "self"),
            result: IPCBridgeTelemetrySnapshotResult(
                paneId: examples.paneId,
                kind: .unavailable,
                unavailableReason: .disabled,
                report: nil
            ),
            privilege: .bridgeTelemetryRead,
            dataScope: .bridgeTelemetry,
            targetKinds: [.pane],
            owner: .bridgeCapability,
            errors: Self.telemetryErrors
        )
        bridgeTelemetryFlush = try IPCBuiltInDescriptorSupport.mutation(
            name: "bridge.telemetry.flush",
            description: "Flush buffered Bridge telemetry and return its settled report.",
            parameters: IPCBridgeTelemetryFlushParams(
                handle: "self",
                correlationId: examples.correlationId
            ),
            result: IPCBridgeTelemetryFlushResult(
                paneId: examples.paneId,
                kind: .unavailable,
                unavailableReason: .disabled,
                report: nil,
                drained: nil
            ),
            metadata: .init(
                privilege: .bridgeTelemetryFlush,
                dataScope: .bridgeTelemetry,
                targetKinds: [.pane],
                owner: .bridgeCapability,
                errors: Self.telemetryErrors)
        )
    }

    private static let telemetryErrors = [
        IPCBuiltInDescriptorSupport.invalidParams,
        IPCBuiltInDescriptorSupport.targetNotFound,
        IPCBuiltInDescriptorSupport.unavailable,
    ]

    var erased: [IPCAnyMethodDescriptor] {
        get throws {
            try [
                IPCAnyMethodDescriptor(erasing: bridgeTelemetrySnapshot),
                IPCAnyMethodDescriptor(erasing: bridgeTelemetryFlush),
            ]
        }
    }
}

package struct IPCBridgeMethodDescriptors: Sendable {
    package let review: IPCBridgeReviewMethodDescriptors
    package let control: IPCBridgeControlMethodDescriptors
    package let telemetry: IPCBridgeTelemetryMethodDescriptors

    init(inputs: IPCBuiltInMethodCatalogInputs) throws {
        review = try IPCBridgeReviewMethodDescriptors(inputs: inputs)
        control = try IPCBridgeControlMethodDescriptors(examples: inputs.examples)
        telemetry = try IPCBridgeTelemetryMethodDescriptors(examples: inputs.examples)
    }

    var erased: [IPCAnyMethodDescriptor] {
        get throws { try review.erased + control.erased + telemetry.erased }
    }
}
