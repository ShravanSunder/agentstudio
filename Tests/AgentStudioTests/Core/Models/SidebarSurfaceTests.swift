import Foundation
import Testing

@testable import AgentStudio

@Suite("SidebarSurface")
struct SidebarSurfaceTests {
    @Test("encodes to raw string")
    func encodesToRawString() {
        #expect(SidebarSurface.repos.rawValue == "repos")
        #expect(SidebarSurface.inbox.rawValue == "inbox")
    }

    @Test("round-trips through JSON")
    func roundTripsJSON() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for surface in [SidebarSurface.repos, .inbox] {
            let data = try encoder.encode(surface)
            let decoded = try decoder.decode(SidebarSurface.self, from: data)
            #expect(decoded == surface)
        }
    }
}
