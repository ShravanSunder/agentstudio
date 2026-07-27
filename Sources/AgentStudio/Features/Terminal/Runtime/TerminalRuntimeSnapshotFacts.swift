import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

package struct TerminalRuntimeSnapshotFacts: Sendable, Equatable {
    package let rendererHealthy: Bool?
    package let readOnly: Bool?
    package let secureInput: Bool?
}

@MainActor
package protocol TerminalRuntimeSnapshotFactProviding: PaneRuntime {
    func terminalRuntimeSnapshotFacts() -> TerminalRuntimeSnapshotFacts
}
