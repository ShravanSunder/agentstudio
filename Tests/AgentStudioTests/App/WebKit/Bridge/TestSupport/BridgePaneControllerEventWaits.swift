import Foundation

@MainActor
enum BridgePaneControllerEventWaits {
    /// Suspends on the controller's observation notification and returns the
    /// exact value that satisfied the caller's predicate.
    static func waitForValue<Value>(_ readValue: @escaping @MainActor () -> Value?) async -> Value {
        while true {
            if let value = readValue() { return value }
            await withCheckedContinuation { continuation in
                withObservationTracking {
                    _ = readValue()
                } onChange: {
                    continuation.resume()
                }
            }
        }
    }

    static func waitForValue<Value: Sendable>(
        _ readValue: @escaping @MainActor () -> Value?,
        milestone: String,
        lastObservation: @escaping @MainActor () -> String
    ) async throws -> Value {
        try await awaitBridgeWebKitMilestone(
            "\(milestone); last=\(lastObservation())"
        ) {
            await waitForValue(readValue)
        }
    }
}

struct BridgeWebKitMilestoneHang: Error, CustomStringConvertible {
    let milestone: String
    let lastObservation: String

    var description: String {
        "WebKit milestone \(milestone) did not settle; last=\(lastObservation)"
    }
}
