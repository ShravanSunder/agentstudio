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
        hangBoundNanoseconds: UInt64,
        lastObservation: @escaping @MainActor () -> String
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            let wait = BoundedBridgePaneObservationWait(
                readValue: readValue,
                milestone: milestone,
                hangBoundNanoseconds: hangBoundNanoseconds,
                lastObservation: lastObservation,
                continuation: continuation
            )
            wait.start()
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

@MainActor
private final class BoundedBridgePaneObservationWait<Value: Sendable> {
    private let readValue: @MainActor () -> Value?
    private let milestone: String
    private let hangBoundNanoseconds: UInt64
    private let lastObservation: @MainActor () -> String
    private var continuation: CheckedContinuation<Value, any Error>?
    private var deadlineTask: Task<Void, Never>?

    init(
        readValue: @escaping @MainActor () -> Value?,
        milestone: String,
        hangBoundNanoseconds: UInt64,
        lastObservation: @escaping @MainActor () -> String,
        continuation: CheckedContinuation<Value, any Error>
    ) {
        self.readValue = readValue
        self.milestone = milestone
        self.hangBoundNanoseconds = hangBoundNanoseconds
        self.lastObservation = lastObservation
        self.continuation = continuation
    }

    func start() {
        deadlineTask = Task { [self] in
            try? await ContinuousClock().sleep(for: .nanoseconds(Int64(hangBoundNanoseconds)))
            guard !Task.isCancelled else { return }
            finish(
                .failure(
                    BridgeWebKitMilestoneHang(
                        milestone: milestone,
                        lastObservation: lastObservation()
                    )))
        }
        observe()
    }

    private func observe() {
        guard continuation != nil else { return }
        let value = withObservationTracking {
            readValue()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        if let value { finish(.success(value)) }
    }

    private func finish(_ result: Result<Value, any Error>) {
        guard let continuation else { return }
        self.continuation = nil
        deadlineTask?.cancel()
        continuation.resume(with: result)
    }
}
