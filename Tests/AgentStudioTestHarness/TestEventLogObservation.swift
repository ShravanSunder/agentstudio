import Darwin
import Foundation
@_spi(ForToolsIntegrationOnly) import Testing

/// Keep the case-ID SPI in this one test-only adapter. v0 encodes the same
/// description: swift-testing 48d727cc1cf4, ABI/Encoded/ABI.EncodedTest.swift:129.
/// The public current getters live in Running/Runner.RuntimeState.swift:211,247;
/// Parameterization/Test.Case.ID.swift:50 exposes the case ID through this SPI.
package struct TestEventLogIdentity: Sendable {
    let testID: String
    let caseID: String?

    static var current: Self? {
        guard let test = Test.current else { return nil }
        return Self(
            testID: String(describing: test.id),
            caseID: Test.Case.current.map { String(describing: $0.id) }
        )
    }
}

/// Metadata is a trailing JSON field, leaving existing log payloads intact.
/// Clock.swift:29-33 uses CLOCK_UPTIME_RAW for the v0 stream's absolute instant;
/// integer seconds/nanos retain its epoch without a wall-clock conversion.
struct TestEventLogObservation: Encodable {
    let seconds: Int64?
    let nanoseconds: Int?
    let identity: TestEventLogIdentity?
    let waiterID: UInt64?

    init(identity: TestEventLogIdentity?, waiterID: UInt64?) {
        var instant = timespec()
        if clock_gettime(CLOCK_UPTIME_RAW, &instant) == 0 {
            seconds = Int64(instant.tv_sec)
            nanoseconds = instant.tv_nsec
        } else {
            seconds = nil
            nanoseconds = nil
        }
        self.identity = TestEventLogIdentity.current ?? identity
        self.waiterID = waiterID
    }

    private enum CodingKeys: String, CodingKey {
        case clockDomain, seconds, nanoseconds, testID, caseID, waiterID
    }

    func encode(to encoder: any Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode("CLOCK_UPTIME_RAW", forKey: .clockDomain)
        try fields.encode(seconds, forKey: .seconds)
        try fields.encode(nanoseconds, forKey: .nanoseconds)
        try fields.encode(identity?.testID, forKey: .testID)
        try fields.encode(identity?.caseID, forKey: .caseID)
        try fields.encode(waiterID, forKey: .waiterID)
    }
}
