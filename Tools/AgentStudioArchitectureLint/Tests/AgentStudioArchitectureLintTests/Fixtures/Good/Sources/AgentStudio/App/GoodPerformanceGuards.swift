import Foundation

enum AppPolicies {
    static let refreshThresholdMilliseconds = 250
}

@MainActor
struct GoodPerformanceOwner {
    let keyedRows: [Int: Int]

    func observe() {
        withObservationTracking {
            _ = keyedRows[1]
        } onChange: {
        }
    }

    @concurrent nonisolated func load() async throws {
        _ = try Data(contentsOf: URL(fileURLWithPath: "/tmp/input"))
    }
}
