import Foundation

// S3 RED stand-in: only the planned no-store/S0 boundary is declared; no CLI store is opened.
enum LifecycleReportBoundary: Equatable, Sendable {
    case noStore
    case stored(storeId: UUID, sequence: Int64)
}

// S3 RED stand-in: declare the intake boundary without wiring it into initialization.
protocol LifecycleReportIntaking: Sendable {
    func captureListenerReadyBoundary() async throws -> LifecycleReportBoundary
    func takeIn(through boundary: LifecycleReportBoundary) async throws
}

// S3 RED stand-in: the plan's no-store intake has no rows or effects; replace at S4.
struct NoStoreLifecycleReportIntake: LifecycleReportIntaking {
    func captureListenerReadyBoundary() async throws -> LifecycleReportBoundary { .noStore }
    func takeIn(through boundary: LifecycleReportBoundary) async throws {}
}
