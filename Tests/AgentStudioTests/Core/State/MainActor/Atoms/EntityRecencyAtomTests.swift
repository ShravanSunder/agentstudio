import AgentStudioInfrastructure
import Foundation
import Observation
import Testing

@testable import AgentStudioCore

private final class EntityRecencyObservationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedChangeCount = 0

    var changeCount: Int {
        lock.withLock { storedChangeCount }
    }

    func recordChange() {
        lock.withLock { storedChangeCount += 1 }
    }
}

@MainActor
@Suite("EntityRecencyAtom")
struct EntityRecencyAtomTests {
    @Test("application owner deduplicates and deterministically orders each kind")
    func applicationOwnerDeduplicatesAndOrdersEachKind() throws {
        let atom = ApplicationEntityRecencyAtom(
            now: { Date(timeIntervalSince1970: 300) }
        )
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

    @Test("application retention preserves every identity inside the activity horizon")
    func applicationRetentionPreservesActivityHorizon() throws {
        let atom = ApplicationEntityRecencyAtom(
            now: { Date(timeIntervalSince1970: 16) }
        )

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

        #expect(atom.recentEntities.count == 32)
        #expect(atom.recentEntities.filter { $0.entity.storageKind == "repository" }.count == 16)
        #expect(atom.recentEntities.filter { $0.entity.storageKind == "worktree" }.count == 16)
    }

    @Test("application retention removes identities older than the activity horizon")
    func applicationRetentionRemovesExpiredActivity() throws {
        let referenceDate = Date(timeIntervalSince1970: 10_000_000)
        let atom = ApplicationEntityRecencyAtom(now: { referenceDate })
        let horizon = AppPolicies.EntityRecency.applicationActivityHorizon

        atom.hydrate([
            try ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "aaaaaaaaaaaaaaaa"),
                interaction: .opened,
                lastInteractedAt: referenceDate.addingTimeInterval(-horizon)
            ),
            try ApplicationEntityRecency(
                entity: .repository(repositoryStableKey: "bbbbbbbbbbbbbbbb"),
                interaction: .opened,
                lastInteractedAt: referenceDate.addingTimeInterval(-horizon).addingTimeInterval(-1)
            ),
        ])

        #expect(atom.recentEntities.map(\.entity) == [.repository(repositoryStableKey: "aaaaaaaaaaaaaaaa")])
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
        let recordedAtom = ApplicationEntityRecencyAtom(
            now: { Date(timeIntervalSince1970: 200) }
        )
        let hydratedAtom = ApplicationEntityRecencyAtom(
            now: { Date(timeIntervalSince1970: 200) }
        )

        for fact in facts {
            recordedAtom.record(fact)
        }
        hydratedAtom.hydrate(facts)

        #expect(hydratedAtom.recentEntities == recordedAtom.recentEntities)
        #expect(recordedAtom.hydrationDisposition == .pending)
        #expect(hydratedAtom.hydrationDisposition == .authoritative)
    }

    @Test("unavailable clear makes empty recency authoritative")
    func unavailableClearMakesEmptyRecencyAuthoritative() {
        let atom = ApplicationEntityRecencyAtom()

        #expect(atom.hydrationDisposition == .pending)
        atom.clear()

        #expect(atom.hydrationDisposition == .authoritative)
        #expect(atom.recentEntities.isEmpty)
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

    @Test("workspace keyed recency ignores changes for another pane")
    func workspaceKeyedRecencyObservesOnlyTheRequestedPane() throws {
        let atom = WorkspaceEntityRecencyAtom()
        let workspaceID = UUID(uuidString: "00000000-0000-7000-8000-000000000001")!
        let observedPaneID = UUID(uuidString: "00000000-0000-7000-8000-000000000002")!
        let unrelatedPaneID = UUID(uuidString: "00000000-0000-7000-8000-000000000003")!
        atom.hydrate(workspaceID: workspaceID, recentEntities: [])
        let observationRecorder = EntityRecencyObservationRecorder()

        _ = withObservationTracking {
            atom.recency(for: .pane(paneID: observedPaneID))
        } onChange: {
            observationRecorder.recordChange()
        }

        atom.record(
            try WorkspaceEntityRecency(
                workspaceID: workspaceID,
                entity: .pane(paneID: unrelatedPaneID),
                interaction: .focused,
                lastInteractedAt: Date(timeIntervalSince1970: 100)
            )
        )
        #expect(observationRecorder.changeCount == 0)

        atom.record(
            try WorkspaceEntityRecency(
                workspaceID: workspaceID,
                entity: .pane(paneID: observedPaneID),
                interaction: .focused,
                lastInteractedAt: Date(timeIntervalSince1970: 200)
            )
        )
        #expect(observationRecorder.changeCount == 1)
    }
}
