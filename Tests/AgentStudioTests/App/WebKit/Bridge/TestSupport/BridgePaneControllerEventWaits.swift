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
}
