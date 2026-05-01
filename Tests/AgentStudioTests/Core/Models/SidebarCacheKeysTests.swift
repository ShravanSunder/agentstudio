import Foundation
import Testing

@testable import AgentStudio

struct SidebarCacheKeysTests {
    @Test
    func sidebarCacheKeys_encodeAsRawStrings() throws {
        let encoded = try JSONEncoder().encode(SidebarGroupKey("repo:agent-studio"))

        #expect(String(data: encoded, encoding: .utf8) == "\"repo:agent-studio\"")
    }

    @Test
    func sidebarCacheKeys_decodeFromRawStrings() throws {
        let decoded = try JSONDecoder().decode(
            InboxNotificationGroupKey.self,
            from: Data("\"kind:terminal\"".utf8)
        )

        #expect(decoded == InboxNotificationGroupKey("kind:terminal"))
    }
}
