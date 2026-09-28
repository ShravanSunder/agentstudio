import AgentStudioInfrastructure
import Foundation

@testable import AgentStudioBridge

actor BridgeProductWebKitCarrierTraceRecorder: BridgePerformanceTraceRecording {
    enum TraceCondition: Sendable {
        case reviewPublication

        func isSatisfied(by trace: BridgeProductWebKitCarrierTrace) -> Bool {
            switch self {
            case .reviewPublication:
                trace.hasReviewMetadataPublication
            }
        }
    }

    private struct TraceWaiter {
        let condition: TraceCondition
        let continuation: CheckedContinuation<BridgeProductWebKitCarrierTrace?, Never>
    }

    private var samples: [BridgeTelemetrySample] = []
    private var traceWaiters: [UUID: TraceWaiter] = [:]

    func record(sample: BridgeTelemetrySample, receivedAtUnixNano _: UInt64) {
        samples.append(sample)
        let trace = scrubbedTrace()
        let satisfiedWaiterIDs = traceWaiters.keys.filter { waiterID in
            traceWaiters[waiterID]?.condition.isSatisfied(by: trace) == true
        }
        for waiterID in satisfiedWaiterIDs {
            traceWaiters.removeValue(forKey: waiterID)?.continuation.resume(returning: trace)
        }
    }

    func waitForTrace(_ condition: TraceCondition) async -> BridgeProductWebKitCarrierTrace? {
        let current = scrubbedTrace()
        if condition.isSatisfied(by: current) { return current }
        let waiterID = UUIDv7.generate()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(returning: nil)
                    return
                }
                let current = scrubbedTrace()
                if condition.isSatisfied(by: current) {
                    continuation.resume(returning: current)
                } else {
                    traceWaiters[waiterID] = .init(condition: condition, continuation: continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelTraceWaiter(waiterID) }
        }
    }

    private func cancelTraceWaiter(_ waiterID: UUID) {
        traceWaiters.removeValue(forKey: waiterID)?.continuation.resume(returning: nil)
    }

    func recordDrop(
        reason _: BridgeTelemetryDropReason,
        droppedCount _: Int,
        firstRejectedEventName _: String?,
        receivedAtUnixNano _: UInt64
    ) {}

    func drain() {}

    func scrubbedTrace() -> BridgeProductWebKitCarrierTrace {
        BridgeProductWebKitCarrierTrace(
            fileMetadataPhases: phases(
                eventName: "performance.bridge.swift.metadata_bootstrap_lifecycle",
                protocolName: "worktree-file"
            ),
            panePresentationEvents: panePresentationEvents(),
            reviewMetadataPhases: phases(
                eventName: "performance.bridge.swift.metadata_bootstrap_lifecycle",
                protocolName: "review"
            ),
            reviewPublicationPhases: phases(
                eventName: "performance.bridge.swift.review_metadata_publication",
                protocolName: "review"
            )
        )
    }

    private func panePresentationEvents() -> [BridgeProductWebKitCarrierPanePresentationTrace] {
        samples.compactMap { sample in
            guard sample.name == "performance.bridge.swift.pane_presentation",
                let presentationRevision =
                    sample.numericAttributes["agentstudio.bridge.presentation.revision"],
                let resultReason =
                    sample.stringAttributes["agentstudio.bridge.result_reason"],
                let stage = sample.stringAttributes["agentstudio.bridge.phase"]
            else { return nil }
            return BridgeProductWebKitCarrierPanePresentationTrace(
                presentationRevision: Int(presentationRevision),
                resultReason: resultReason,
                stage: stage
            )
        }
    }

    private func phases(eventName: String, protocolName: String) -> [String] {
        samples.compactMap { sample in
            guard sample.name == eventName,
                sample.stringAttributes["agentstudio.bridge.protocol"] == protocolName
            else { return nil }
            return sample.stringAttributes["agentstudio.bridge.phase"]
        }
    }
}
