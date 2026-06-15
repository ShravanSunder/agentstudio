import Testing

@testable import AgentStudio

@Suite("TerminalGeometryDiagnostics")
@MainActor
struct TerminalGeometryDiagnosticsTests {
    @Test("diagnostics count incoherent geometry by reason")
    func diagnosticsCountIncoherentGeometryByReason() {
        let diagnostics = TerminalGeometryDiagnostics()

        diagnostics.recordViolation(
            reason: "displaySurface",
            status: .incoherent(scaleDrift: true, sizeDrift: false)
        )
        diagnostics.recordViolation(
            reason: "displaySurface",
            status: .incoherent(scaleDrift: false, sizeDrift: true)
        )
        diagnostics.recordViolation(
            reason: "forceGeometrySync",
            status: .incoherent(scaleDrift: true, sizeDrift: true)
        )

        #expect(diagnostics.violationCount(reason: "displaySurface") == 2)
        #expect(diagnostics.violationCount(reason: "forceGeometrySync") == 1)
    }

    @Test("diagnostics ignore coherent and unavailable geometry")
    func diagnosticsIgnoreCoherentAndUnavailableGeometry() {
        let diagnostics = TerminalGeometryDiagnostics()

        diagnostics.recordViolation(reason: "displaySurface", status: .coherent)
        diagnostics.recordViolation(reason: "displaySurface", status: .unavailable(.missingWindow))

        #expect(diagnostics.violationCount(reason: "displaySurface") == 0)
        #expect(diagnostics.violationSnapshot().isEmpty)
    }
}
