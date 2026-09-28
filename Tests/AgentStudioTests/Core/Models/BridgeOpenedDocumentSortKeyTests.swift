import AgentStudioInfrastructure
import Foundation
import Testing

@testable import AgentStudioCore

@Suite("Bridge opened-document sort key")
struct BridgeOpenedDocumentSortKeyTests {
    @Test("same-millisecond opens and an ahead-of-wall floor stay in admission order")
    func logicalMillisecondMint() {
        let first = mintOpenedDocumentSortKey(wallMillis: 1000, floorMillis: 999)
        let second = mintOpenedDocumentSortKey(wallMillis: 1000, floorMillis: first.newFloorMillis)
        let hydrated = mintOpenedDocumentSortKey(wallMillis: 1000, floorMillis: 1200)

        #expect(first.newFloorMillis == 1000)
        #expect(second.newFloorMillis == 1001)
        #expect(hydrated.newFloorMillis == 1201)
        #expect(first.key.uuidString < second.key.uuidString)
        #expect(second.key.uuidString < hydrated.key.uuidString)
        #expect(UUIDv7.isV7(first.key))
        #expect(UUIDv7.isV7(second.key))
        #expect(UUIDv7.isV7(hydrated.key))
    }
}
