import Foundation
import Testing

@testable import AgentStudio

@Suite
struct PaneArrangementIdentityTests {
    @Test
    func mainPaneId_roundTripsThroughCodableAsUUID() throws {
        let raw = UUIDv7.generate()
        let value = MainPaneId(raw)

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(MainPaneId.self, from: data)

        #expect(decoded.rawValue == raw)
    }

    @Test
    func drawerPaneId_roundTripsThroughCodableAsUUID() throws {
        let raw = UUIDv7.generate()
        let value = DrawerPaneId(raw)

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(DrawerPaneId.self, from: data)

        #expect(decoded.rawValue == raw)
    }

    @Test
    func setConversion_exposesRawUUIDsExplicitly() {
        let first = UUIDv7.generate()
        let second = UUIDv7.generate()
        let mainIds: Set<MainPaneId> = [MainPaneId(first), MainPaneId(second)]
        let drawerIds: Set<DrawerPaneId> = [DrawerPaneId(first), DrawerPaneId(second)]

        #expect(mainIds.rawUUIDs == Set([first, second]))
        #expect(drawerIds.rawUUIDs == Set([first, second]))
    }

    @Test
    func drawerId_roundTripsThroughCodableAsUUID() throws {
        let raw = UUID()
        let value = DrawerId(raw)

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(DrawerId.self, from: data)

        #expect(decoded.rawValue == raw)
    }
}
