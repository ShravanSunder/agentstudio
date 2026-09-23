import AgentStudioAppIPC
import AgentStudioIPCTransport
import AgentStudioInfrastructure
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioTestSupport

/// A1 through the real server: registry, pane-agent authorization, the App's
/// own-pane port over the real pane graph, and the existing handlers, on the
/// debug channel and on the stable channel's registry and exposure rules.
@MainActor
@Suite("App IPC pane-agent control", .serialized)
struct AgentStudioIPCPaneAgentControlTests {
    init() { installTestCoreAtomsIfNeeded() }

    @Test(
        "a main-terminal agent runs own-pane commands on its terminal and its drawer child",
        arguments: [AgentStudioIPCChannel.debug, .stable]
    )
    func mainTerminalAgentRunsOwnPaneCommands(channel: AgentStudioIPCChannel) async throws {
        let harness = try await PaneAgentControlHarness.make(channel: channel)
        defer { harness.tearDown() }
        let token = try harness.agentToken(boundTo: harness.mainPaneId)
        let before = harness.workspaceFacts()

        for target in [harness.mainPaneId, harness.drawerChildPaneId] {
            let send = try await harness.response(
                token: token, method: "terminal.send",
                params: .object([
                    "handle": .string(target.uuidString), "input": .string("ls\n"),
                    "correlationId": .string(UUIDv7.generate().uuidString),
                ]))
            let status = try await harness.response(
                token: token, method: "terminal.status", params: .object(["handle": .string(target.uuidString)]))
            #expect(send.error == nil, "terminal.send \(target): \(String(describing: send.error))")
            #expect(status.error == nil, "terminal.status \(target): \(String(describing: status.error))")
        }
        let scrolled = try await withIsolatedCommandDispatcher(
            configure: { AppCommandDispatcher.shared.handler = harness.commandHarness.controller },
            body: {
                try await harness.response(
                    token: token, method: "command.execute",
                    params: try harness.command(
                        .scrollToBottom, arguments: try harness.paneArguments(harness.drawerChildPaneId)))
            })
        let listing = try await harness.response(token: token, method: "pane.list", params: .object([:]))

        #expect(scrolled.error == nil, "scrollToBottom: \(String(describing: scrolled.error))")
        #expect(listing.error == nil)
        let mainCommands = try #require(harness.runtimesByPaneId[harness.mainPaneId]).receivedCommands
        let childCommands = try #require(harness.runtimesByPaneId[harness.drawerChildPaneId]).receivedCommands
        #expect(terminalCommandNames(mainCommands) == ["sendInput(ls\n)"])
        #expect(terminalCommandNames(childCommands) == ["sendInput(ls\n)", "scrollToBottom"])
        #expect(harness.workspaceFacts() == before)
    }

    @Test(
        "everything outside the agent's own pane is refused by name with no effect",
        arguments: [AgentStudioIPCChannel.debug, .stable]
    )
    func outsideOwnPaneIsNotYetAllowed(channel: AgentStudioIPCChannel) async throws {
        let harness = try await PaneAgentControlHarness.make(channel: channel)
        defer { harness.tearDown() }
        let token = try harness.agentToken(boundTo: harness.mainPaneId)
        let own = harness.mainPaneId.uuidString
        let before = harness.workspaceFacts()

        let otherPaneInput = try await harness.response(
            token: token, method: "terminal.send",
            params: .object([
                "handle": .string(harness.otherPaneId.uuidString), "input": .string("ls\n"),
                "correlationId": .string(UUIDv7.generate().uuidString),
            ]))
        let focus = try await harness.response(
            token: token, method: "pane.focus",
            params: .object(["handle": .string(own), "correlationId": .string(UUIDv7.generate().uuidString)]))
        let bridge = try await harness.response(
            token: token, method: "bridge.diff.getPackage", params: .object(["handle": .string(own)]))
        let zoom = try await harness.response(
            token: token, method: "command.execute",
            params: try harness.command(.zoomPane, arguments: try harness.paneArguments(harness.mainPaneId)))
        let split = try await harness.response(
            token: token, method: "command.execute",
            params: try harness.command(.splitRight, arguments: try harness.paneArguments(harness.mainPaneId)))
        let closeSelf = try await harness.response(
            token: token, method: "pane.close",
            params: .object(["handle": .string(own), "correlationId": .string(UUIDv7.generate().uuidString)]))
        let unknown = try await harness.response(token: token, method: "bogus.method", params: .object([:]))

        #expect(PaneAgentRefusal(otherPaneInput) == .notYetAllowed("terminal.send"))
        #expect(PaneAgentRefusal(focus) == .notYetAllowed("pane.focus"))
        #expect(PaneAgentRefusal(bridge) == .notYetAllowed("bridge.diff.getPackage"))
        #expect(PaneAgentRefusal(zoom) == .notYetAllowed("zoomPane"))
        #expect(PaneAgentRefusal(split) == .notYetAllowed("splitRight"))
        #expect(PaneAgentRefusal(closeSelf) == .refusedForAgent("pane.close"))
        #expect(unknown.error?.code == -32_601)
        #expect(try #require(harness.runtimesByPaneId[harness.otherPaneId]).receivedCommands.isEmpty)
        #expect(harness.workspaceFacts() == before)
    }

    @Test(
        "a drawer-terminal agent owns only itself and cannot add drawer children",
        arguments: [AgentStudioIPCChannel.debug, .stable]
    )
    func drawerTerminalAgentOwnsOnlyItself(channel: AgentStudioIPCChannel) async throws {
        let harness = try await PaneAgentControlHarness.make(channel: channel)
        defer { harness.tearDown() }
        let token = try harness.agentToken(boundTo: harness.drawerChildPaneId)
        let before = harness.workspaceFacts()

        let ownStatus = try await harness.response(
            token: token, method: "terminal.status",
            params: .object(["handle": .string(harness.drawerChildPaneId.uuidString)]))
        let parentStatus = try await harness.response(
            token: token, method: "terminal.status",
            params: .object(["handle": .string(harness.mainPaneId.uuidString)]))
        let closeSelf = try await harness.response(
            token: token, method: "command.execute",
            params: try harness.command(
                .closeDrawerPane,
                arguments: try harness.drawerChildArguments(
                    parent: harness.mainPaneId, child: harness.drawerChildPaneId)))
        let addDrawerChild = try await harness.response(
            token: token, method: "drawer.addPane",
            params: .object([
                "parentPaneHandle": .string("self"), "correlationId": .string(UUIDv7.generate().uuidString),
            ]))

        #expect(ownStatus.error == nil)
        #expect(PaneAgentRefusal(parentStatus) == .notYetAllowed("terminal.status"))
        #expect(PaneAgentRefusal(closeSelf) == .notYetAllowed("closeDrawerPane"))
        #expect(PaneAgentRefusal(addDrawerChild) == .refusedForAgent("drawer.addPane"))
        #expect(harness.workspaceFacts() == before)
    }

    @Test(
        "established session methods keep bound-pane admission for pane agents",
        arguments: [AgentStudioIPCChannel.debug, .stable]
    )
    func establishedSessionMethodsAreUnchanged(channel: AgentStudioIPCChannel) async throws {
        let harness = try await PaneAgentControlHarness.make(channel: channel)
        defer { harness.tearDown() }
        let token = try harness.agentToken(boundTo: harness.mainPaneId)

        let own = try await harness.response(
            token: token, method: "session.query", params: .object(["handle": .string(harness.mainPaneId.uuidString)]))
        let drawerChild = try await harness.response(
            token: token, method: "session.query",
            params: .object(["handle": .string(harness.drawerChildPaneId.uuidString)]))

        #expect(own.error == nil, "session.query own: \(String(describing: own.error))")
        #expect(drawerChild.error?.code == -32_002)
        #expect(PaneAgentRefusal(drawerChild)?.reason == "missingGrant")
    }

    @Test(
        "an agent adds a background drawer child, targets it by the returned handle, and cannot add Bridge content",
        arguments: [AgentStudioIPCChannel.debug, .stable]
    )
    func agentAddsAndTargetsBackgroundDrawerChild(channel: AgentStudioIPCChannel) async throws {
        let harness = try await PaneAgentControlHarness.make(channel: channel)
        defer { harness.tearDown() }
        let token = try harness.agentToken(boundTo: harness.mainPaneId)
        let before = harness.workspaceFacts()

        let add = try await harness.response(
            token: token, method: "drawer.addPane",
            params: .object([
                "parentPaneHandle": .string("self"),
                "content": .object(["kind": .string("browser"), "url": .string("https://example.com")]),
                "correlationId": .string(UUIDv7.generate().uuidString),
            ]))
        let added = try decodeAddResult(add)
        let snapshot = try await harness.response(
            token: token, method: "pane.snapshot", params: .object(["handle": .string(added.childHandle)]))
        let bridge = try await harness.response(
            token: token, method: "drawer.addPane",
            params: .object([
                "parentPaneHandle": .string("self"), "content": .object(["kind": .string("bridge")]),
                "correlationId": .string(UUIDv7.generate().uuidString),
            ]))

        #expect(added.parentPaneId == harness.mainPaneId)
        #expect(snapshot.error == nil, "pane.snapshot child: \(String(describing: snapshot.error))")
        #expect(PaneAgentRefusal(bridge) == .refusedForAgent("drawer.addPane"))
        let after = harness.workspaceFacts()
        #expect(after.drawerChildIds == before.drawerChildIds + [added.childPaneId])
        #expect(after.isDrawerExpanded == before.isDrawerExpanded)
        #expect(after.activeDrawerChildId == before.activeDrawerChildId)
        #expect(after.activeTabId == before.activeTabId)
        #expect(after.activePaneId == before.activePaneId)
    }

    private func decodeAddResult(_ response: JSONRPCResponseMessage) throws -> IPCDrawerAddPaneResult {
        let result = try #require(response.result, "drawer.addPane: \(String(describing: response.error))")
        return try JSONDecoder().decode(IPCDrawerAddPaneResult.self, from: JSONEncoder().encode(result))
    }

    @Test(
        "an agent closes its own drawer child through the catalog command",
        arguments: [AgentStudioIPCChannel.debug, .stable]
    )
    func agentClosesItsOwnDrawerChild(channel: AgentStudioIPCChannel) async throws {
        let harness = try await PaneAgentControlHarness.make(channel: channel)
        defer { harness.tearDown() }
        let token = try harness.agentToken(boundTo: harness.mainPaneId)

        let close = try await withIsolatedCommandDispatcher(
            configure: { AppCommandDispatcher.shared.handler = harness.commandHarness.controller },
            body: {
                try await harness.response(
                    token: token, method: "command.execute",
                    params: try harness.command(
                        .closeDrawerPane,
                        arguments: try harness.drawerChildArguments(
                            parent: harness.mainPaneId, child: harness.drawerChildPaneId)))
            })

        #expect(close.error == nil, "closeDrawerPane: \(String(describing: close.error))")
        #expect(harness.store.paneAtom.pane(harness.drawerChildPaneId) == nil)
        #expect(harness.store.paneAtom.pane(harness.mainPaneId) != nil)
    }
}

/// Names only the terminal commands a runtime received; runtime commands are
/// not Equatable.
@MainActor
func terminalCommandNames(_ envelopes: [RuntimeCommandEnvelope]) -> [String] {
    envelopes.map { envelope in
        switch envelope.command {
        case .terminal(.sendInput(let input)): "sendInput(\(input))"
        case .terminal(.scrollToBottom): "scrollToBottom"
        case .terminal(.scrollPageFractional(let fraction)): "scrollPageFractional(\(fraction))"
        case .terminal(.jumpToPrompt(let delta)): "jumpToPrompt(\(delta))"
        default: "other"
        }
    }
}
