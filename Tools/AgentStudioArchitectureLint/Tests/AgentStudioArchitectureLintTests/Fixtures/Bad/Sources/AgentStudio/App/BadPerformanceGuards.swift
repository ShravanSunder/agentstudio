import Foundation

@MainActor
struct BadPerformanceOwner {
    let rows: [Int]
    let refreshThresholdMilliseconds = 250

    func observe() {
        withObservationTracking {
            _ = paneSnapshot()
        } onChange: {
        }
    }

    func arrange() {
        _ = rows.sorted()
    }

    nonisolated func load() async throws {
        _ = try Data(contentsOf: URL(fileURLWithPath: "/tmp/input"))
    }

    private func paneSnapshot() -> [Int] { [] }
}

@MainActor
extension BadPerformanceOwner {
    func arrangeInMainActorExtension() {
        _ = rows.sorted()
    }
}

struct BadMainActorFunctionOwner {
    let rows: [Int]

    @MainActor
    func arrangeInMainActorFunction() {
        _ = rows.sorted()
    }
}
