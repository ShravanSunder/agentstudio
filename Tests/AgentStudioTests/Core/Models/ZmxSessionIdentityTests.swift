import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Zmx cleanup identity validation")
struct ZmxSessionIdentityTests {
    enum InvalidField: CaseIterable, Sendable {
        case processGroup
        case duplicateProcess
        case daemonMicroseconds
        case terminalMicroseconds
    }

    @Test("trusted identity round trips without changing the incarnation")
    func validIdentityRoundTrips() throws {
        let identity = makeIdentity()
        #expect(try ZmxSessionIdentity.decode(identity.encoded()) == identity)
    }

    @Test("inconsistent process evidence is rejected", arguments: InvalidField.allCases)
    func inconsistentProcessEvidenceIsRejected(field: InvalidField) throws {
        let encoded = try makeIdentity(invalidField: field).encoded()
        #expect(throws: ZmxSessionControlFailure.invalidIdentity) {
            try ZmxSessionIdentity.decode(encoded)
        }
    }

    private func makeIdentity(invalidField: InvalidField? = nil) -> ZmxSessionIdentity {
        ZmxSessionIdentity(
            version: 1, bootID: "identity-test-boot",
            daemon: .init(
                pid: 1200, startSeconds: 100,
                startMicroseconds: invalidField == .daemonMicroseconds ? 1_000_000 : 123),
            terminalLeader: .init(
                pid: invalidField == .duplicateProcess ? 1200 : 1201,
                startSeconds: 100,
                startMicroseconds: invalidField == .terminalMicroseconds ? 1_000_000 : 456),
            processGroupID: invalidField == .processGroup ? 2200 : invalidField == .duplicateProcess ? 1200 : 1201,
            sessionCreatedAt: 100)
    }
}
