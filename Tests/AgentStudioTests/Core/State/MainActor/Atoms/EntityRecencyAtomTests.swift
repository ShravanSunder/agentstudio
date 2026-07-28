import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("EntityRecencyAtom")
struct EntityRecencyAtomTests {
    @Test("application owner deduplicates and deterministically orders each kind")
    func applicationOwnerDeduplicatesAndOrdersEachKind() throws {
        let atom = ApplicationEntityRecencyAtom()
        let tiedTimestamp = Date(timeIntervalSince1970: 100)

        try atom.record(
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "bbbbbbbbbbbbbbbb"),
                interaction: .opened,
                lastInteractedAt: tiedTimestamp
            )
        )
        try atom.record(
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "aaaaaaaaaaaaaaaa"),
                interaction: .opened,
                lastInteractedAt: tiedTimestamp
            )
        )
        try atom.record(
            ApplicationEntityRecency(
                entity: .worktree(worktreeStableKey: "cccccccccccccccc"),
                interaction: .opened,
                lastInteractedAt: Date(timeIntervalSince1970: 200)
            )
        )
        try atom.record(
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "bbbbbbbbbbbbbbbb"),
                interaction: .opened,
                lastInteractedAt: Date(timeIntervalSince1970: 300)
            )
        )

        #expect(
            atom.recentEntities.map(\.entity)
                == [
                    .repository(repositoryStableKey: "bbbbbbbbbbbbbbbb"),
                    .worktree(worktreeStableKey: "cccccccccccccccc"),
                    .repository(repositoryStableKey: "aaaaaaaaaaaaaaaa"),
                ]
        )
    }

    @Test("application retention is independent per entity kind")
    func applicationRetentionIsIndependentPerEntityKind() throws {
        let atom = ApplicationEntityRecencyAtom()

        for index in 0..<16 {
            try atom.record(
                ApplicationEntityRecency(
                    entity: .repository(repositoryStableKey: String(format: "%016x", index)),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: Double(index))
                )
            )
            try atom.record(
                ApplicationEntityRecency(
                    entity: .worktree(worktreeStableKey: String(format: "%016x", index + 100)),
                    interaction: .opened,
                    lastInteractedAt: Date(timeIntervalSince1970: Double(index))
                )
            )
        }

        #expect(atom.recentEntities.count == 30)
        #expect(atom.recentEntities.filter { $0.entity.storageKind == "repository" }.count == 15)
        #expect(atom.recentEntities.filter { $0.entity.storageKind == "worktree" }.count == 15)
    }

    @Test("hydration produces the same bounded deterministic order as recording")
    func hydrationMatchesRecordingOrder() throws {
        let facts = try [
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "bbbbbbbbbbbbbbbb"),
                interaction: .opened,
                lastInteractedAt: Date(timeIntervalSince1970: 100)
            ),
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "aaaaaaaaaaaaaaaa"),
                interaction: .opened,
                lastInteractedAt: Date(timeIntervalSince1970: 100)
            ),
            ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "bbbbbbbbbbbbbbbb"),
                interaction: .opened,
                lastInteractedAt: Date(timeIntervalSince1970: 200)
            ),
        ]
        let recordedAtom = ApplicationEntityRecencyAtom()
        let hydratedAtom = ApplicationEntityRecencyAtom()

        for fact in facts {
            recordedAtom.record(fact)
        }
        hydratedAtom.hydrate(facts)

        #expect(hydratedAtom.recentEntities == recordedAtom.recentEntities)
    }

    @Test("workspace owner isolates hydration and clearing by explicit workspace")
    func workspaceOwnerIsolatesHydrationAndClearing() throws {
        let atom = WorkspaceEntityRecencyAtom()
        let firstWorkspaceID = UUID()
        let secondWorkspaceID = UUID()
        let firstPaneID = UUID()
        let secondPaneID = UUID()

        atom.hydrate(
            workspaceID: firstWorkspaceID,
            recentEntities: [
                try WorkspaceEntityRecency(
                    workspaceID: firstWorkspaceID,
                    entity: .pane(paneID: firstPaneID),
                    interaction: .focused,
                    lastInteractedAt: Date(timeIntervalSince1970: 100)
                )
            ]
        )
        atom.hydrate(
            workspaceID: secondWorkspaceID,
            recentEntities: [
                try WorkspaceEntityRecency(
                    workspaceID: secondWorkspaceID,
                    entity: .pane(paneID: secondPaneID),
                    interaction: .focused,
                    lastInteractedAt: Date(timeIntervalSince1970: 200)
                )
            ]
        )

        #expect(atom.workspaceID == secondWorkspaceID)
        #expect(atom.recentEntities.map(\.entity) == [.pane(paneID: secondPaneID)])

        atom.clear()

        #expect(atom.workspaceID == nil)
        #expect(atom.recentEntities.isEmpty)
    }
}
