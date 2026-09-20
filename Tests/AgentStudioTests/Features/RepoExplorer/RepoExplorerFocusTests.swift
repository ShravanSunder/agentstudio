import AgentStudioCore
import AgentStudioInfrastructure
import AppKit
import Testing

@testable import AgentStudioRepoExplorer

@MainActor
@Suite("RepoExplorer focus publishing", .serialized)
struct RepoExplorerFocusTests {
    @Test("list entry republishes ownership after late workspace restore", arguments: [false, true])
    func listEntryRepairsClearedRuntimeFocus(fromFilter: Bool) {
        let harness = SidebarKeyboardWindowHarness()
        defer { harness.close() }
        #expect(harness.interaction.requestListFocus())
        if fromFilter {
            harness.interaction.requestFilterFocus()
        }
        #expect(harness.uiState.sidebarHasFocus)

        // UIStateStore restores after window presentation; hydrate clears this
        // runtime fact without changing the already-focused native responder.
        harness.uiState.setSidebarHasFocus(false)

        #expect(harness.interaction.requestListFocus())
        #expect(harness.window.firstResponder === harness.host)
        #expect(harness.uiState.sidebarHasFocus)
        #expect(harness.interaction.isListKeyboardActive)
    }

    @Test("the real list responder publishes sidebar ownership")
    func nativeListFocusPublishesOwnership() {
        let harness = SidebarKeyboardWindowHarness()
        defer { harness.close() }

        #expect(harness.window.makeFirstResponder(harness.host))
        #expect(harness.interaction.focusedRegion == .list)
        #expect(harness.uiState.sidebarHasFocus)
        #expect(harness.interaction.isListKeyboardActive)

        #expect(harness.window.makeFirstResponder(harness.field))
        #expect(harness.interaction.focusedRegion == .unfocused)
        #expect(!harness.uiState.sidebarHasFocus)
    }

    @Test("filter entry and return preserve text and restore the native list responder")
    func filterEntryAndReturnPreserveQuery() {
        let harness = SidebarKeyboardWindowHarness()
        defer { harness.close() }
        harness.field.stringValue = "prf19"
        #expect(harness.window.makeFirstResponder(harness.host))

        #expect(RepoExplorerView.requestFilterFocus(on: harness.host))
        #expect(harness.filterRequests == 1)
        #expect(harness.window.firstResponder !== harness.host)
        #expect(harness.interaction.focusedRegion == .filter)
        #expect(harness.uiState.sidebarHasFocus)
        #expect(!harness.interaction.isListKeyboardActive)

        #expect(harness.interaction.requestListFocus())
        harness.interaction.filterFocusDidChange(isFocused: false)
        #expect(harness.window.firstResponder === harness.host)
        #expect(harness.interaction.focusedRegion == .list)
        #expect(harness.uiState.sidebarHasFocus)
        #expect(harness.field.stringValue == "prf19")
    }

    @Test("late filter callbacks cannot clear a newer list focus")
    func staleFilterCallbacksPreserveListFocus() {
        let harness = SidebarKeyboardWindowHarness()
        defer { harness.close() }
        #expect(harness.window.makeFirstResponder(harness.host))
        harness.interaction.requestFilterFocus()
        #expect(harness.interaction.requestListFocus())

        harness.interaction.filterFocusDidChange(isFocused: true)
        harness.interaction.filterFocusDidChange(isFocused: false)

        #expect(harness.window.firstResponder === harness.host)
        #expect(harness.interaction.focusedRegion == .list)
        #expect(harness.uiState.sidebarHasFocus)
    }

    @Test("sidebar command specs complete accepted list input and preserve rejected input")
    func sidebarCommandCompletionFollowsAcceptedDispatch() throws {
        let harness = SidebarKeyboardWindowHarness()
        defer { harness.close() }
        #expect(harness.window.makeFirstResponder(harness.host))

        harness.host.keyDown(with: try harness.event("p", keyCode: 35))
        #expect(harness.commands == [.showPanesSidebar])
        #expect(harness.returnRequests == 1)
        #expect(harness.window.firstResponder === harness.field.currentEditor())
        #expect(!harness.interaction.isListKeyboardActive)

        #expect(harness.interaction.requestListFocus())
        harness.host.keyDown(with: try harness.event("p", keyCode: 35))
        #expect(harness.commands == [.showPanesSidebar, .showPanesSidebar])
        #expect(harness.returnRequests == 2)
        #expect(!harness.interaction.isListKeyboardActive)

        #expect(harness.interaction.requestListFocus())
        harness.host.keyDown(with: try harness.event("r", keyCode: 15))
        #expect(harness.commands == [.showPanesSidebar, .showPanesSidebar, .showReposSidebar])
        #expect(harness.returnRequests == 3)
        #expect(!harness.interaction.isListKeyboardActive)

        #expect(harness.interaction.requestListFocus())
        harness.host.keyDown(with: try harness.event("f", keyCode: 3))
        #expect(
            harness.commands
                == [.showPanesSidebar, .showPanesSidebar, .showReposSidebar, .filterSidebar]
        )
        #expect(harness.returnRequests == 3)
        #expect(harness.window.firstResponder === harness.field.currentEditor())
        #expect(harness.interaction.focusedRegion == .filter)
        #expect(!harness.interaction.isListKeyboardActive)

        #expect(harness.interaction.requestListFocus())
        harness.acceptsCommands = false
        harness.host.keyDown(with: try harness.event("p", keyCode: 35))
        #expect(harness.commands.count == 4)
        #expect(harness.returnRequests == 3)
        #expect(harness.window.firstResponder === harness.host)
        #expect(harness.interaction.isListKeyboardActive)
        harness.acceptsCommands = true

        harness.commands.removeAll()
        harness.permitsNavigation = false
        harness.host.keyDown(with: try harness.event("p", keyCode: 35))
        #expect(harness.commands.isEmpty)

        harness.permitsNavigation = true
        harness.interaction.requestFilterFocus()
        harness.host.keyDown(with: try harness.event("r", keyCode: 15))
        #expect(harness.commands.isEmpty)
        #expect(harness.interaction.focusedRegion == .filter)
    }

    @Test("Escape requests return focus and detach clears only this host's reporting")
    func escapeAndDetachRespectHostLifetime() throws {
        let harness = SidebarKeyboardWindowHarness()
        defer { harness.close() }
        #expect(harness.window.makeFirstResponder(harness.host))

        harness.host.keyDown(with: try harness.event("\u{1B}", keyCode: 53))
        #expect(harness.returnRequests == 1)
        harness.host.detach()
        #expect(harness.interaction.focusedRegion == .unfocused)
        #expect(!harness.uiState.sidebarHasFocus)
        #expect(!harness.host.acceptsFirstResponder)
    }
}

@MainActor
private final class SidebarKeyboardWindowHarness {
    let interaction = RepoExplorerKeyboardInteraction()
    let uiState = WorkspaceSidebarState()
    let host: RepoExplorerMaterializationHost
    let window: NSWindow
    let field = NSTextField(frame: NSRect(x: 0, y: 440, width: 300, height: 28))
    var permitsNavigation = true
    var acceptsCommands = true
    var commands: [AppCommand] = []
    var filterRequests = 0
    var returnRequests = 0

    init() {
        host = RepoExplorerMaterializationHost(
            lifetimeID: RepoExplorerMaterializationHostLifetimeID(rawValue: UUIDv7.generate()),
            initialDemandEpoch: 1,
            initialPresentation: .noRepositories,
            makeContentChild: { preconditionFailure("This focus fixture remains rowless") },
            onFeedback: { _ in }
        )
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 480))
        host.frame = NSRect(x: 0, y: 0, width: 320, height: 420)
        container.addSubview(host)
        container.addSubview(field)
        window = NSWindow(
            contentRect: container.bounds,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = container
        interaction.configure(
            RepoExplorerKeyboardCallbacks(
                canInterpretListInput: { [weak self] in self?.permitsNavigation == true },
                onFilterFocusRequest: { [weak self] in
                    guard let self else { return }
                    filterRequests += 1
                    _ = window.makeFirstResponder(field)
                    interaction.filterFocusDidChange(isFocused: true)
                },
                onReturnFocusRequest: { [weak self] in
                    guard let self else { return }
                    returnRequests += 1
                    _ = window.makeFirstResponder(field)
                },
                onSidebarFocusChange: { [weak self] in self?.uiState.setSidebarHasFocus($0) },
                onCommandRequest: { [weak self] command in
                    guard let self, acceptsCommands else { return false }
                    commands.append(command)
                    if command == .filterSidebar {
                        interaction.requestFilterFocus()
                    }
                    return true
                }
            )
        )
        host.installKeyboardInteraction(interaction)
    }

    func event(_ characters: String, keyCode: UInt16) throws -> NSEvent {
        try #require(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    func close() {
        host.detach()
        window.close()
    }
}
