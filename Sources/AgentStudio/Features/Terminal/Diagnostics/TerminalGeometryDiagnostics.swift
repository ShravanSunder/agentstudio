import Foundation

@MainActor
final class TerminalGeometryDiagnostics {
    static let shared = TerminalGeometryDiagnostics()

    private var violationCountsByReason: [String: Int] = [:]

    func recordViolation(
        reason: StaticString,
        status: Ghostty.SurfaceView.SurfaceGeometryCoherenceStatus
    ) {
        guard case .incoherent = status else { return }
        violationCountsByReason[String(describing: reason), default: 0] += 1
    }

    func violationCount(reason: StaticString) -> Int {
        violationCountsByReason[String(describing: reason), default: 0]
    }

    func violationSnapshot() -> [String: Int] {
        violationCountsByReason
    }
}
