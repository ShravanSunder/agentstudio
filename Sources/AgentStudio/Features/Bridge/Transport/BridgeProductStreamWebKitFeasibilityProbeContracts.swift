import Foundation

extension BridgeProductStreamProbeRequestBody {
    static let strictJSONMemberVocabulary = BridgeProductStrictJSONMemberVocabulary(
        Set([
            "bodyByteCount",
            "cancellationObserved",
            "kind",
            "measuredRequestCount",
            "nearCapTiming",
            "padding",
            "phase",
            "sampleIndex",
            "sequence",
            "stream",
            "warmupRequestCount",
            "workerEncodeDurationsMicroseconds",
            "workerFetchCompletionDurationsMicroseconds",
            "workerObservedExactFrames",
            "workerObservedIncrementalFrames",
        ])
    )
}

extension BridgeWebKitFeasibilityProducerKind {
    init?(workerStreamName: String) {
        switch workerStreamName {
        case "completed": self = .completedStream
        case "cancellable": self = .cancellableStream
        default: return nil
        }
    }

    var workerStreamName: String {
        switch self {
        case .completedStream: "completed"
        case .cancellableStream: "cancellable"
        }
    }
}
