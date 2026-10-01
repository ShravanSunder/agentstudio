import AgentStudioCore
import Foundation

/// Ephemeral ps input. argv0 must never enter the durable observation row.
package struct ForegroundProcessSample: Sendable {
    package let incarnation: ProcessIncarnation
    package let processGroupId: Int32
    package let foregroundGroupId: Int32
    package let argv0: String
}

package struct ForegroundPsPass: Sendable {
    package let samples: [ForegroundProcessSample]
    package let complete: Bool
}

/// S2 RED compile-level stand-in; no ps, socket or filesystem work yet.
package struct DarwinTerminalForegroundProbe: TerminalForegroundProbing {
    package init(
        sessionDirectory: String, bootId: String,
        sessionControl: (any ZmxSessionControlling)? = nil,
        readSamples: (@Sendable () async throws -> ForegroundPsPass)? = nil
    ) {}

    package func probeForeground(of sessions: [ZmxSessionID]) async throws -> [ZmxSessionID: ForegroundSnapshot] {
        throw ForegroundImplementationMissing.s2
    }

    package static func classify(
        leader: ProcessIncarnation, samples: [ForegroundProcessSample], complete: Bool
    ) -> ForegroundProgram {
        .unknown
    }
}
