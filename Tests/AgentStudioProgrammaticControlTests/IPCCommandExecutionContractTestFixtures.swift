import AgentStudioProgrammaticControl
import Foundation

enum IPCCommandExecutionContractTestFixtures {
    static let commandId = IPCCommandIdentifier(rawValue: "futureTypedCommand")
    static let correlationId = uuid("01994abc-2000-7000-8000-000000000001")
    static let operationId = uuid("01994abc-2000-7000-8000-000000000002")
    static let appliedPaneId = uuid("01994abc-2000-7000-8000-000000000003")

    static func request(
        commandId: IPCCommandIdentifier = commandId,
        correlationId: UUID = correlationId,
        arguments: IPCCommandArguments = .noArguments
    ) -> IPCCommandExecutionRequest {
        IPCCommandExecutionRequest(
            commandId: commandId,
            correlationId: correlationId,
            arguments: arguments
        )
    }

    static func allResults() -> [IPCCommandExecutionResult] {
        [
            .applied(
                IPCCommandAppliedResult(
                    commandId: commandId,
                    correlationId: correlationId
                )
            ),
            .accepted(
                IPCCommandAcceptedResult(
                    commandId: commandId,
                    correlationId: correlationId,
                    operationId: operationId
                )
            ),
            .presented(
                IPCCommandPresentedResult(
                    commandId: commandId,
                    correlationId: correlationId
                )
            ),
            .unavailable(
                IPCCommandUnavailableResult(
                    commandId: commandId,
                    correlationId: correlationId,
                    reason: .featureUnavailable
                )
            ),
            .partial(
                IPCCommandPartialResult(
                    commandId: commandId,
                    correlationId: correlationId,
                    appliedEffects: [
                        IPCCommandEffectReference(kind: .pane, id: appliedPaneId)
                    ],
                    reason: .ownerRejectedRemainingEffects
                )
            ),
            .uncertain(
                IPCCommandUncertainResult(
                    commandId: commandId,
                    correlationId: correlationId,
                    reason: .ownerSettlementUnknown
                )
            ),
        ]
    }

    static func encodedObject(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private static func uuid(_ rawValue: String) -> UUID {
        guard let identifier = UUID(uuidString: rawValue) else {
            preconditionFailure("Invalid command execution fixture UUID")
        }
        return identifier
    }
}
