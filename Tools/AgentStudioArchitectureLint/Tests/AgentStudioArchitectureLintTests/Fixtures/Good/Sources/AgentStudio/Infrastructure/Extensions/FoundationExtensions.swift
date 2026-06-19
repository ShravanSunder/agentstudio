import Foundation

struct AsyncDelay {
    static func clock(_ clock: any Clock<Duration> & Sendable) -> Self {
        Self { duration in
            try await clock.sleep(for: duration)
        }
    }

    private let operation: (Duration) async throws -> Void

    init(_ operation: @escaping (Duration) async throws -> Void) {
        self.operation = operation
    }
}
