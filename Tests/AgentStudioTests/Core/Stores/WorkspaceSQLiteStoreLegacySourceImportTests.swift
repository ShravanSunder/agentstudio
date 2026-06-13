import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("WorkspaceSQLiteStoreLegacySourceImportTests", .serialized)
struct WorkspaceSQLiteStoreLegacySourceImportTests {
    @Test("restore maps legacy pane source payload into launch directory and live facets")
    func restoreMapsLegacyPaneSourcePayloadIntoLaunchDirectoryAndLiveFacets() async throws {
        let workspaceId = UUID()
        let repoId = UUID()
        let worktreeId = UUID()
        let launchDirectory = URL(filePath: "/tmp/legacy-source-worktree")
        let fixture = try makeWorkspaceSQLiteBridgeFixture(workspaceId: workspaceId)
        let persistor = WorkspacePersistor(
            workspacesDir: FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        )
        #expect(persistor.ensureDirectory())
        let createdAt = Date(timeIntervalSince1970: 1_700_000_410)
        let pane = Pane(
            content: .terminal(.init(provider: .zmx, lifetime: .persistent)),
            metadata: .init(
                launchDirectory: launchDirectory,
                createdAt: createdAt,
                title: "Legacy Source Pane"
            )
        )
        let tab = Tab(paneId: pane.id, name: "Legacy Source Tab")
        let state = WorkspacePersistor.PersistableState(
            id: workspaceId,
            name: "Legacy Source Workspace",
            repos: [
                CanonicalRepo(
                    id: repoId,
                    name: "legacy-source",
                    repoPath: launchDirectory
                )
            ],
            worktrees: [
                CanonicalWorktree(
                    id: worktreeId,
                    repoId: repoId,
                    name: "main",
                    path: launchDirectory,
                    isMainWorktree: true
                )
            ],
            panes: [pane],
            tabs: [tab],
            activeTabId: tab.id,
            createdAt: createdAt,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_420)
        )
        try writeLegacySourceWorkspaceJSON(
            .init(
                state: state,
                workspaceId: workspaceId,
                paneIndex: 0,
                repoId: repoId,
                worktreeId: worktreeId,
                launchDirectory: launchDirectory,
                persistor: persistor
            )
        )
        let store = WorkspaceStore(
            persistor: persistor,
            sqliteDatastore: workspaceSQLiteDatastore(from: fixture.backend)
        )

        await store.restoreAsync()

        let importedPane = try #require(store.paneAtom.pane(pane.id))
        #expect(importedPane.metadata.launchDirectory == launchDirectory)
        #expect(importedPane.metadata.facets.repoId == repoId)
        #expect(importedPane.metadata.facets.worktreeId == worktreeId)
        #expect(importedPane.metadata.facets.cwd == launchDirectory)
        let paneGraph = try fixture.coreRepository.fetchPaneGraph(workspaceId: workspaceId)
        let paneRecord = try #require(paneGraph.panes.single)
        #expect(paneRecord.metadata.launchDirectory == launchDirectory)
        #expect(paneRecord.metadata.durableFacets.repoId == repoId)
        #expect(paneRecord.metadata.durableFacets.worktreeId == worktreeId)
        #expect(paneRecord.metadata.durableFacets.cwd == launchDirectory)
    }
}

private struct LegacySourceWorkspaceJSONProps {
    let state: WorkspacePersistor.PersistableState
    let workspaceId: UUID
    let paneIndex: Int
    let repoId: UUID
    let worktreeId: UUID
    let launchDirectory: URL
    let persistor: WorkspacePersistor
}

private enum WorkspaceSQLiteBridgeLegacySourceJSONError: Error {
    case invalidRoot
    case missingPanes
    case missingPane
    case missingMetadata
}

private func writeLegacySourceWorkspaceJSON(_ props: LegacySourceWorkspaceJSONProps) throws {
    let encoded = try JSONEncoder().encode(props.state)
    guard var root = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else {
        throw WorkspaceSQLiteBridgeLegacySourceJSONError.invalidRoot
    }
    guard var panes = root["panes"] as? [[String: Any]] else {
        throw WorkspaceSQLiteBridgeLegacySourceJSONError.missingPanes
    }
    guard panes.indices.contains(props.paneIndex) else {
        throw WorkspaceSQLiteBridgeLegacySourceJSONError.missingPane
    }
    var pane = panes[props.paneIndex]
    guard var metadata = pane["metadata"] as? [String: Any] else {
        throw WorkspaceSQLiteBridgeLegacySourceJSONError.missingMetadata
    }

    metadata.removeValue(forKey: "launchDirectory")
    metadata["facets"] = ["tags": []]
    metadata["source"] = [
        "worktree": [
            "worktreeId": props.worktreeId.uuidString,
            "repoId": props.repoId.uuidString,
            "launchDirectory": props.launchDirectory.absoluteString,
        ]
    ]
    pane["metadata"] = metadata
    panes[props.paneIndex] = pane
    root["panes"] = panes

    let legacyData = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    try legacyData.write(
        to: URL(filePath: props.persistor.canonicalWorkspaceStatePath(for: props.workspaceId)),
        options: .atomic
    )
}
