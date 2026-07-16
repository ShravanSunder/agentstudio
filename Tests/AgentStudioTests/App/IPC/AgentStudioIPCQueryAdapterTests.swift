import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AgentStudio IPC query adapter")
struct AgentStudioIPCQueryAdapterTests {
    @Test("system capabilities mirror the app-composed phase-a registry without backend namespaces")
    func systemCapabilitiesMirrorAppComposedPhaseARegistryWithoutBackendNamespaces() throws {
        let harness = try QueryAdapterHarness()

        let capabilities = try harness.adapter.systemCapabilities()
        let methodNames = capabilities.methods.map(\.name)

        #expect(methodNames.contains("system.identify"))
        #expect(methodNames.contains("pane.snapshot"))
        #expect(methodNames.contains("terminal.send"))
        #expect(!methodNames.contains { $0.hasPrefix("zmx.") })
        #expect(methodNames == methodNames.sorted())
    }

    @Test("pane snapshot contribution declares the sensitive fields it excludes")
    func paneSnapshotContributionDeclaresTheSensitiveFieldsItExcludes() throws {
        let contribution = try #require(
            try AgentStudioIPCContributionRegistry.phaseAComposition().methodContributions.first {
                $0.definition.name == "pane.snapshot"
            }
        )

        #expect(
            contribution.securityContract.sensitiveDataExclusions == [
                "cwd",
                "paneTitle",
                "rawTerminalOutput",
                "rawRuntimePayload",
                "tabTitle",
                "url",
                "zmxSessionIdentifier",
            ])
    }

    @Test("current window fails closed when no workspace window is active")
    func currentWindowFailsClosedWhenNoWorkspaceWindowIsActive() throws {
        let harness = try QueryAdapterHarness(windowSnapshot: .empty)

        do {
            _ = try harness.adapter.currentWindow()
            Issue.record("currentWindow unexpectedly succeeded without an active window")
        } catch let error as AppIPCQueryError {
            #expect(error.reason == .noActiveWindow)
        }
    }

    @Test("lists current workspace and active pane from sanitized app snapshots")
    func listsCurrentWorkspaceAndActivePaneFromSanitizedSnapshots() throws {
        let windowId = UUID()
        let store = makeWorkspaceStore()
        let pane = store.createPane(title: "Build Pane")
        let tab = Tab(paneId: pane.id, name: "Build Tab")
        store.appendTab(tab)
        store.setActiveTab(tab.id)

        let harness = try QueryAdapterHarness(
            store: store,
            windowSnapshot: .singleActiveWindow(windowId)
        )

        let windows = try harness.adapter.listWindows().windows
        let workspace = try harness.adapter.currentWorkspace().workspace
        let panes = try harness.adapter.listPanes().panes
        let currentPane = try harness.adapter.currentPane()

        #expect(windows.map(\.id) == [windowId])
        #expect(windows.first?.isCurrent == true)
        #expect(workspace.id == store.workspaceId)
        #expect(workspace.name == "Default Workspace")
        #expect(workspace.tabCount == 1)
        #expect(workspace.paneCount == 1)
        #expect(panes.map(\.id) == [pane.id])
        #expect(panes.first?.contentKind == .terminal)
        #expect(panes.first?.isActive == true)
        #expect(currentPane.pane.id == pane.id)
        #expect(currentPane.tab?.id == tab.id)
    }

    @Test("pane snapshot reports target not found for unknown pane id")
    func paneSnapshotReportsTargetNotFoundForUnknownPaneId() throws {
        let store = makeWorkspaceStore()
        let pane = store.createPane(title: "Known")
        store.appendTab(Tab(paneId: pane.id))
        let harness = try QueryAdapterHarness(store: store, windowSnapshot: .singleActiveWindow(UUID()))

        do {
            _ = try harness.adapter.snapshotPane(UUID())
            Issue.record("snapshotPane unexpectedly succeeded for an unknown pane")
        } catch let error as AppIPCQueryError {
            #expect(error.reason == .targetNotFound)
        }
    }

    @Test("pane snapshots do not expose titles cwd url or zmx session identifiers")
    func paneSnapshotsDoNotExposeTitlesCwdURLOrZmxSessionIdentifiers() throws {
        let store = makeWorkspaceStore()
        let secretCWD = URL(fileURLWithPath: "/tmp/agentstudio-secret-cwd")
        let terminalPane = store.createPane(
            content: .terminal(
                TerminalState(
                    provider: .zmx,
                    lifetime: .persistent,
                    zmxSessionID: try #require(ZmxSessionID(restoring: "secret-zmx-session"))
                )
            ),
            metadata: PaneMetadata(launchDirectory: secretCWD, title: "Secret Terminal")
        )
        let webPane = store.createPane(
            content: .webview(
                WebviewState(
                    url: try #require(URL(string: "https://secret.example.local/private")),
                    title: "Secret Web",
                    showNavigation: true
                )
            ),
            metadata: PaneMetadata(title: "Secret Web")
        )
        store.appendTab(Tab(paneId: terminalPane.id, name: "Secret Tab"))
        store.setActiveTab(store.tabs[0].id)

        let harness = try QueryAdapterHarness(store: store, windowSnapshot: .singleActiveWindow(UUID()))
        let terminalSnapshot = try harness.adapter.snapshotPane(terminalPane.id)
        let encodedTerminal = try encodedJSONString(terminalSnapshot)
        let paneList = try encodedJSONString(harness.adapter.listPanes())

        #expect(paneList.contains(webPane.id.uuidString))
        #expect(!encodedTerminal.contains("Secret Terminal"))
        #expect(!encodedTerminal.contains("Secret Web"))
        #expect(!encodedTerminal.contains("Secret Tab"))
        #expect(!paneList.contains("Secret Terminal"))
        #expect(!paneList.contains("Secret Web"))
        #expect(!paneList.contains("Secret Tab"))
        #expect(!encodedTerminal.contains("secret-zmx-session"))
        #expect(!encodedTerminal.contains(secretCWD.path))
        #expect(!paneList.contains("secret.example.local"))
        #expect(!paneList.contains("private"))
    }
}

@MainActor
private struct QueryAdapterHarness {
    let adapter: AgentStudioIPCQueryAdapter

    init(
        store: WorkspaceStore = makeWorkspaceStore(),
        windowSnapshot: WorkspaceWindowLifecycleSnapshot = .singleActiveWindow(UUID())
    ) throws {
        adapter = AgentStudioIPCQueryAdapter(
            runtimeId: UUID(),
            accessMode: .agentStudioOnly,
            appVersion: "test",
            methodRegistry: try AgentStudioIPCContributionRegistry.phaseARegistry(),
            workspaceStore: store,
            windowLifecycleReader: FakeWorkspaceWindowLifecycleReader(snapshot: windowSnapshot)
        )
    }
}

private struct FakeWorkspaceWindowLifecycleReader: WorkspaceWindowLifecycleReading {
    let snapshotValue: WorkspaceWindowLifecycleSnapshot

    init(snapshot: WorkspaceWindowLifecycleSnapshot) {
        snapshotValue = snapshot
    }

    func snapshot() -> WorkspaceWindowLifecycleSnapshot {
        snapshotValue
    }
}

extension WorkspaceWindowLifecycleSnapshot {
    fileprivate static var empty: Self {
        Self(
            registeredWindowIds: [],
            keyWindowId: nil,
            focusedWindowId: nil,
            preferredWorkspaceWindowId: nil
        )
    }

    fileprivate static func singleActiveWindow(_ windowId: UUID) -> Self {
        Self(
            registeredWindowIds: [windowId],
            keyWindowId: windowId,
            focusedWindowId: windowId,
            preferredWorkspaceWindowId: windowId
        )
    }
}

@MainActor
private func makeWorkspaceStore() -> WorkspaceStore {
    let tempDir = FileManager.default.temporaryDirectory
        .appending(path: "agentstudio-ipc-query-adapter-\(UUID().uuidString)")
    return WorkspaceStore(
        workspacePersistenceRevisionOwner: WorkspacePersistenceRevisionOwner())
}

private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let string = String(bytes: data, encoding: .utf8) else {
        throw EncodedJSONStringError.invalidUTF8
    }
    return string
}

private enum EncodedJSONStringError: Error {
    case invalidUTF8
}
