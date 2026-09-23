import AgentStudioProgrammaticControl
import Foundation
import Testing

@Suite("IPC declared result boundaries")
struct IPCResultBoundaryTests {
    @Test("discovery names distinct durable, presentation, partial and uncertain boundaries")
    func resultBoundariesRemainDistinct() throws {
        let boundaries: [IPCResultSemantics] = [
            .accepted, .durable, .applied, .presented, .partial, .uncertain,
        ]
        #expect(Set(boundaries.map(\.rawValue)).count == boundaries.count)
        for boundary in boundaries {
            #expect(
                try JSONDecoder().decode(IPCResultSemantics.self, from: JSONEncoder().encode(boundary))
                    == boundary
            )
        }
    }
}
