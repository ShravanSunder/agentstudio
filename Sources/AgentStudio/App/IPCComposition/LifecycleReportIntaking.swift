import Foundation

/// The immutable high-water boundary captured when the listener becomes ready.
enum LifecycleReportBoundary: Equatable, Sendable {
    case noStore
    case stored(storeId: UUID, sequence: Int64)
}

/// App initialization waits for historical lifecycle disposition through this boundary.
protocol LifecycleReportIntaking: Sendable {
    func captureListenerReadyBoundary() async throws -> LifecycleReportBoundary
    func takeIn(through boundary: LifecycleReportBoundary) async throws
}

// Planned S4 dependency: no-store intake has no historical rows; replace when the CLI store lands.
struct NoStoreLifecycleReportIntake: LifecycleReportIntaking {
    func captureListenerReadyBoundary() async throws -> LifecycleReportBoundary { .noStore }
    func takeIn(through boundary: LifecycleReportBoundary) async throws {}
}
