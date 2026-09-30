import JavaScriptCore
import Testing
import WebKit

@testable import AgentStudioInfrastructure

@MainActor
@Suite
struct WebInteractionManagementScriptTests {

    @Test
    func test_makeUserScript_blockedTrue_embedsInitialBlockedTrue() throws {
        let fixture = try #require(makeJavaScriptFixture())
        #expect(fixture.initializationExceptionMessage == nil)
        let script = WebInteractionManagementScript.makeUserScript(blockInteraction: true)
        fixture.execute(script.source)

        #expect(fixture.exceptionMessage == nil)
        #expect(fixture.stringResult(for: "document.documentElement.style.pointerEvents") == "none")
        #expect(
            fixture.stringResult(
                for: "document.documentElement.dataset.agentStudioPrevPointerEvents"
            ) == "auto"
        )
        #expect(fixture.booleanResult(for: "window.__listenerCount() === 4") == true)
        #expect(fixture.booleanResult(for: "window.__captureListenersInstalled()") == true)
        #expect(fixture.stringResult(for: "window.__dispatchDrag('dragover')") == "true|true")
    }

    @Test
    func test_makeUserScript_blockedFalse_embedsInitialBlockedFalse() throws {
        let fixture = try #require(makeJavaScriptFixture())
        #expect(fixture.initializationExceptionMessage == nil)
        let script = WebInteractionManagementScript.makeUserScript(blockInteraction: false)
        fixture.execute(script.source)

        #expect(fixture.exceptionMessage == nil)
        #expect(
            fixture.booleanResult(for: "document.documentElement.style.pointerEvents !== 'none'")
                == true
        )
        #expect(fixture.booleanResult(for: "window.__listenerCount() === 0") == true)
        #expect(fixture.booleanResult(for: "window.__agentStudioManagementInteraction.blocked === false") == true)
    }

    @Test
    func test_makeRuntimeToggleSource_containsStateSetter() throws {
        let fixture = try #require(makeJavaScriptFixture())
        #expect(fixture.initializationExceptionMessage == nil)
        let initialScript = WebInteractionManagementScript.makeUserScript(blockInteraction: true)
        fixture.execute(initialScript.source)

        #expect(fixture.exceptionMessage == nil)
        #expect(fixture.stringResult(for: "document.documentElement.style.pointerEvents") == "none")
        #expect(fixture.booleanResult(for: "window.__listenerCount() === 4") == true)

        let unblockSource = WebInteractionManagementScript.makeRuntimeToggleSource(
            blockInteraction: false
        )
        fixture.execute(unblockSource)

        #expect(fixture.exceptionMessage == nil)
        #expect(fixture.stringResult(for: "document.documentElement.style.pointerEvents") == "auto")
        #expect(
            fixture.booleanResult(
                for: """
                    Object.prototype.hasOwnProperty.call(
                        document.documentElement.dataset,
                        'agentStudioPrevPointerEvents'
                    ) === false
                    """
            ) == true
        )
        #expect(fixture.booleanResult(for: "window.__listenerCount() === 0") == true)
        #expect(fixture.stringResult(for: "window.__dispatchDrag('dragover')") == "false|false")

        let blockSource = WebInteractionManagementScript.makeRuntimeToggleSource(
            blockInteraction: true
        )
        fixture.execute(blockSource)

        #expect(fixture.exceptionMessage == nil)
        #expect(fixture.stringResult(for: "document.documentElement.style.pointerEvents") == "none")
        #expect(fixture.booleanResult(for: "window.__listenerCount() === 4") == true)
        #expect(fixture.booleanResult(for: "window.__captureListenersInstalled()") == true)
        #expect(fixture.stringResult(for: "window.__dispatchDrag('dragover')") == "true|true")
    }
}

@MainActor
private func makeJavaScriptFixture() -> ManagementInteractionJavaScriptFixture? {
    guard let context = JSContext() else { return nil }
    return ManagementInteractionJavaScriptFixture(context: context)
}

@MainActor
private final class ManagementInteractionJavaScriptFixture {
    private let context: JSContext
    let initializationExceptionMessage: String?

    init(context: JSContext) {
        context.evaluateScript(Self.documentFixtureSource)
        self.context = context
        self.initializationExceptionMessage = context.exception?.toString()
    }

    var exceptionMessage: String? {
        context.exception?.toString()
    }

    func execute(_ source: String) {
        context.exception = nil
        context.evaluateScript(source)
    }

    func booleanResult(for expression: String) -> Bool? {
        context.evaluateScript(expression)?.toBool()
    }

    func stringResult(for expression: String) -> String? {
        context.evaluateScript(expression)?.toString()
    }

    private static let documentFixtureSource = """
        var window = {};
        var listenerRegistry = {};
        var document = {
            documentElement: {
                style: {
                    pointerEvents: "auto",
                    removeProperty: function(propertyName) {
                        if (propertyName === "pointer-events") { this.pointerEvents = ""; }
                    }
                },
                dataset: {}
            },
            addEventListener: function(type, handler, capture) {
                var listeners = listenerRegistry[type] || [];
                listeners.push({ handler: handler, capture: capture });
                listenerRegistry[type] = listeners;
            },
            removeEventListener: function(type, handler, capture) {
                var listeners = listenerRegistry[type] || [];
                listenerRegistry[type] = listeners.filter(function(listener) {
                    return listener.handler !== handler || listener.capture !== capture;
                });
            }
        };

        window.document = document;
        window.__listenerCount = function() {
            return Object.keys(listenerRegistry).reduce(function(count, type) {
                return count + listenerRegistry[type].length;
            }, 0);
        };
        window.__captureListenersInstalled = function() {
            var dragEventTypes = ["dragenter", "dragover", "dragleave", "drop"];
            return dragEventTypes.every(function(type) {
                var listeners = listenerRegistry[type] || [];
                return listeners.length === 1 && listeners[0].capture === true;
            });
        };
        window.__dispatchDrag = function(type) {
            var event = {
                defaultPrevented: false,
                propagationStopped: false,
                preventDefault: function() { this.defaultPrevented = true; },
                stopPropagation: function() { this.propagationStopped = true; }
            };
            (listenerRegistry[type] || []).forEach(function(listener) {
                listener.handler(event);
            });
            return event.defaultPrevented + "|" + event.propagationStopped;
        };
        """
}
