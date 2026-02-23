import Testing
import WebKit

@testable import AgentStudio

@MainActor
@Suite
struct WebInteractionManagementScriptTests {

    @Test
    func test_makeUserScript_blockedTrue_embedsInitialBlockedTrue() {
        let script = WebInteractionManagementScript.makeUserScript(blockInteraction: true)
        #expect(script.source.contains("var initialBlocked = true;"))
    }

    @Test
    func test_makeUserScript_blockedFalse_embedsInitialBlockedFalse() {
        let script = WebInteractionManagementScript.makeUserScript(blockInteraction: false)
        #expect(script.source.contains("var initialBlocked = false;"))
    }

    @Test
    func test_makeRuntimeToggleSource_containsStateSetter() {
        let source = WebInteractionManagementScript.makeRuntimeToggleSource(blockInteraction: true)
        #expect(source.contains("setBlocked"))
        #expect(source.contains("window.__agentStudioManagementInteraction"))
    }
}
