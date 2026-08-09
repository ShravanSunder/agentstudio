import AgentStudioInfrastructure
import AgentStudioTestSupport
import Foundation
import GRDB
import Testing

@testable import AgentStudioCore

@MainActor
@Suite("Workspace comparison-intent process restart", .serialized)
struct WorkspaceComparisonIntentProcessRestartTests {
    @Test("process A commits and flushes one symbolic comparison intent")
    func workspaceComparisonIntentRestartProcessACommits() async throws {
        guard let fixture = try restartFixtureFromEnvironment() else { return }

        // Arrange
        try FileManager.default.createDirectory(
            at: fixture.reviewedWorktreeRoot,
            withIntermediateDirectories: true
        )
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Process A failed to prepare its isolated SQLite root")
            return
        }
        let store = WorkspaceStore(sqliteDatastore: datastore)
        guard case .initializedDefaultWorkspace = await store.loadCanonicalComposition() else {
            Issue.record("Process A expected a pristine isolated workspace")
            return
        }
        let selectionRequiredState = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(
                rootPath: fixture.reviewedWorktreeRoot.path,
                comparisonIntent: .init(
                    activeKind: .contribution,
                    contributionTarget: nil
                )
            )
        )
        let pane = Pane(
            id: fixture.paneID,
            content: .bridgePanel(selectionRequiredState),
            metadata: PaneMetadata(
                paneId: PaneId(existingUUID: fixture.paneID),
                contentType: .diff,
                launchDirectory: fixture.reviewedWorktreeRoot,
                title: "Restart comparison intent",
                facets: PaneContextFacets(cwd: fixture.reviewedWorktreeRoot)
            )
        )
        store.paneAtom.addPane(pane)
        store.appendTab(Tab(paneId: fixture.paneID, name: "Restart comparison intent"))
        let committedState = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(
                rootPath: fixture.reviewedWorktreeRoot.path,
                comparisonIntent: fixture.expectedIntent
            )
        )
        let narrowState = BridgePaneState(
            panelKind: .diffViewer,
            source: .workspace(
                rootPath: fixture.reviewedWorktreeRoot.path,
                comparisonIntent: .init(
                    activeKind: .stagedOnly,
                    contributionTarget: fixture.expectedTarget
                )
            )
        )

        // Act
        let initialTargetResult = store.paneAtom.setInitialBridgeContributionTargetIfAbsent(
            fixture.paneID,
            target: fixture.expectedTarget
        )
        let narrowMutationResult = store.paneAtom.updateBridgePaneState(
            fixture.paneID,
            state: narrowState
        )
        let contributionMutationResult = store.paneAtom.updateBridgePaneState(
            fixture.paneID,
            state: committedState
        )
        let flushOutcome = await store.flushAsync()

        // Assert
        #expect(initialTargetResult == .applied(committedState))
        #expect(narrowMutationResult == .applied(narrowState))
        #expect(contributionMutationResult == .applied(committedState))
        #expect(flushOutcome == .persisted)
        print("COMPARISON_INTENT_PROCESS_A_TEST_PID=\(ProcessInfo.processInfo.processIdentifier)")
        print("COMPARISON_INTENT_PROCESS_A_TRANSITION=contribution>stagedOnly>contribution")
        print("COMPARISON_INTENT_PROCESS_A_FLUSH=persisted")
        print("COMPARISON_INTENT_PROCESS_A_PANE_ID=\(fixture.paneID.uuidString)")
    }

    @Test("process B restores the exact symbolic intent without calculated origin")
    func workspaceComparisonIntentRestartProcessBRestores() async throws {
        guard let fixture = try restartFixtureFromEnvironment() else { return }

        // Arrange
        let datastore = fixture.makeDatastore()
        guard case .prepared = await datastore.prepareDatabasesForBoot() else {
            Issue.record("Process B failed to prepare the persisted SQLite root")
            return
        }
        let store = WorkspaceStore(sqliteDatastore: datastore)

        // Act
        let loadResult = await store.loadCanonicalComposition()
        let restoredPane = try #require(store.pane(fixture.paneID))
        let persistedPayload = try fixture.readPersistedBridgePayload()

        // Assert
        guard case .loaded = loadResult else {
            Issue.record("Process B expected to load process A's persisted workspace")
            return
        }
        guard case .bridgePanel(let restoredState) = restoredPane.content else {
            Issue.record("Process B restored a non-Bridge pane for the fixed pane UUID")
            return
        }
        #expect(restoredPane.id == fixture.paneID)
        #expect(
            restoredState.source
                == .workspace(
                    rootPath: fixture.reviewedWorktreeRoot.path,
                    comparisonIntent: fixture.expectedIntent
                )
        )
        let payloadObject = try #require(
            JSONSerialization.jsonObject(with: Data(persistedPayload.utf8)) as? [String: Any]
        )
        #expect(Set(payloadObject.keys) == ["type", "version", "state"])
        #expect(payloadObject["type"] as? String == "bridgePanel")
        #expect(payloadObject["version"] as? Int == 3)
        let stateObject = try #require(payloadObject["state"] as? [String: Any])
        #expect(Set(stateObject.keys) == ["panelKind", "source"])
        #expect(stateObject["panelKind"] as? String == "diffViewer")
        let sourceObject = try #require(stateObject["source"] as? [String: Any])
        #expect(Set(sourceObject.keys) == ["workspace"])
        let workspaceObject = try #require(sourceObject["workspace"] as? [String: Any])
        #expect(Set(workspaceObject.keys) == ["rootPath", "comparisonIntent"])
        #expect(workspaceObject["rootPath"] as? String == fixture.reviewedWorktreeRoot.path)
        let comparisonIntentObject = try #require(
            workspaceObject["comparisonIntent"] as? [String: Any]
        )
        #expect(Set(comparisonIntentObject.keys) == ["activeKind", "contributionTarget"])
        #expect(comparisonIntentObject["activeKind"] as? String == "contribution")
        let contributionTargetObject = try #require(
            comparisonIntentObject["contributionTarget"] as? [String: Any]
        )
        #expect(Set(contributionTargetObject.keys) == ["kind", "name"])
        #expect(contributionTargetObject["kind"] as? String == "ref")
        #expect(contributionTargetObject["name"] as? String == "refs/remotes/origin/review-base")
        print("COMPARISON_INTENT_PROCESS_B_TEST_PID=\(ProcessInfo.processInfo.processIdentifier)")
        print("COMPARISON_INTENT_PROCESS_B_RESTORED_PANE_ID=\(restoredPane.id.uuidString)")
        print("COMPARISON_INTENT_PROCESS_B_RESTORED_TARGET=refs/remotes/origin/review-base")
        print("COMPARISON_INTENT_PROCESS_B_EXACT_PAYLOAD_SHAPE=true")
        print("COMPARISON_INTENT_PROCESS_B_CALCULATED_ORIGIN_PERSISTED=false")
    }
}

private struct WorkspaceComparisonIntentRestartFixture {
    let dataRoot: URL
    let paneID: UUID

    var reviewedWorktreeRoot: URL {
        dataRoot.appending(path: "reviewed-worktree", directoryHint: .isDirectory)
    }

    var expectedIntent: WorkspaceReviewComparisonIntent {
        WorkspaceReviewComparisonIntent(
            activeKind: .contribution,
            contributionTarget: expectedTarget
        )
    }

    var expectedTarget: WorkspaceReviewContributionTarget {
        .ref(name: "refs/remotes/origin/review-base")
    }

    func makeDatastore() -> WorkspaceSQLiteDatastore {
        WorkspaceSQLiteDatastoreFactory(
            coreDatabaseURL: dataRoot.appending(path: "core.sqlite"),
            localDatabaseURL: dataRoot.appending(path: "local.sqlite")
        ).makeDatastore()
    }

    func readPersistedBridgePayload() throws -> String {
        let databasePool = try SQLiteDatabaseFactory.makeFileBackedPool(
            at: dataRoot.appending(path: "core.sqlite"),
            label: "AgentStudio.sqlite.comparison-intent-process-restart"
        )
        defer { try? databasePool.close() }
        return try #require(
            databasePool.read { database in
                try String.fetchOne(
                    database,
                    sql: "SELECT payload_json FROM pane_content_payload WHERE pane_id = ?",
                    arguments: [paneID.uuidString]
                )
            }
        )
    }
}

private func restartFixtureFromEnvironment() throws -> WorkspaceComparisonIntentRestartFixture? {
    let environment = ProcessInfo.processInfo.environment
    guard let dataRootPath = environment["AGENTSTUDIO_COMPARISON_INTENT_RESTART_ROOT"] else {
        return nil
    }
    let paneIDText = try #require(environment["AGENTSTUDIO_COMPARISON_INTENT_RESTART_PANE_ID"])
    let paneID = try #require(UUID(uuidString: paneIDText))
    return WorkspaceComparisonIntentRestartFixture(
        dataRoot: URL(filePath: dataRootPath, directoryHint: .isDirectory),
        paneID: paneID
    )
}
