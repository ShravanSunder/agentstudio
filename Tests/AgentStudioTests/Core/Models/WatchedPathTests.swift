import Foundation
import Testing

@testable import AgentStudio

@Suite struct WatchedPathTests {
    @Test func stableKey_isDeterministic() {
        let a = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        let b = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        #expect(a.stableKey == b.stableKey)
    }

    @Test func stableKey_differentPaths_differ() {
        let a = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        let b = WatchedPath(path: URL(fileURLWithPath: "/other"))
        #expect(a.stableKey != b.stableKey)
    }

    @Test func codable_roundTrips() throws {
        let original = WatchedPath(path: URL(fileURLWithPath: "/projects"))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchedPath.self, from: data)
        #expect(decoded.id == original.id)
        #expect(decoded.path == original.path)
    }
}
