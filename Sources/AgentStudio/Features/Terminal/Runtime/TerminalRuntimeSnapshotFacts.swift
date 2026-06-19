import Foundation

struct TerminalRuntimeSnapshotFacts: Sendable, Equatable {
    let rendererHealthy: Bool?
    let readOnly: Bool?
    let secureInput: Bool?
}

@MainActor
protocol TerminalRuntimeSnapshotFactProviding: PaneRuntime {
    func terminalRuntimeSnapshotFacts() -> TerminalRuntimeSnapshotFacts
}
