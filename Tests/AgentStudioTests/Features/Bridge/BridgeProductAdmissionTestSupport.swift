import Foundation
import Testing

@testable import AgentStudio

struct BridgeProductAdmissionTestContext: Sendable {
    private let gate: BridgeProductAdmissionGate
    let context: BridgeProductAdmissionContext

    static func make() throws -> Self {
        let gate = BridgeProductAdmissionGate()
        return try Self(
            gate: gate,
            context: #require(gate.acquire())
        )
    }

    func close() {
        gate.close()
    }

    func beginControl(
        in session: BridgeProductSession,
        exactRequestBytes: Data,
        presentedCapability: String
    ) async -> BridgeProductSessionControlAdmission {
        await session.beginControl(
            exactRequestBytes: exactRequestBytes,
            presentedCapability: presentedCapability,
            productAdmission: context
        )
    }
}
