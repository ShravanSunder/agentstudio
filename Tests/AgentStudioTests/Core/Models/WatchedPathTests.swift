import Foundation
import Testing

@testable import AgentStudio

@Suite struct WatchedPathTests {
    @Test func defaultIdentity_usesUUIDv7() {
        let watchedPath = WatchedPath(path: URL(fileURLWithPath: "/projects"))

        #expect(UUIDv7.isV7(watchedPath.id))
    }

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

    @Test func codable_roundTripsExplicitLegacyIdentity() throws {
        let legacyIdentity = try #require(
            UUID(uuidString: "5A1714F8-3CF8-46D4-AD1C-18B78C56B216")
        )
        let original = WatchedPath(
            id: legacyIdentity,
            path: URL(fileURLWithPath: "/projects"),
            addedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchedPath.self, from: data)

        #expect(!UUIDv7.isV7(legacyIdentity))
        #expect(decoded == original)
    }
}
