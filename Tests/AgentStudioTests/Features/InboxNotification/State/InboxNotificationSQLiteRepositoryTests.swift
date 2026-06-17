import Foundation
import GRDB
import Testing

@testable import AgentStudio

@MainActor
@Suite("InboxNotificationSQLiteRepository")
struct InboxNotificationSQLiteRepositoryTests {
    @Test("notification rows round trip every persisted source, activity, and claim column")
    func notificationRowsRoundTripEveryPersistedSourceActivityAndClaimColumn() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000001")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let paneId = UUID(uuidString: "20000000-0000-0000-0000-000000000011")!
        let tabId = UUID(uuidString: "20000000-0000-0000-0000-000000000012")!
        let repoId = UUID(uuidString: "20000000-0000-0000-0000-000000000013")!
        let worktreeId = UUID(uuidString: "20000000-0000-0000-0000-000000000014")!
        let parentPaneId = UUID(uuidString: "20000000-0000-0000-0000-000000000015")!
        let burstWindowId = UUID(uuidString: "20000000-0000-0000-0000-000000000016")!
        let activitySessionId = UUID(uuidString: "20000000-0000-0000-0000-000000000017")!
        let claimSessionId = UUID(uuidString: "20000000-0000-0000-0000-000000000018")!
        let paneNotification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000021")!,
            timestamp: Date(timeIntervalSince1970: 1000),
            kind: .unseenActivity,
            title: "Activity",
            body: "Rows changed",
            source: .pane(
                .init(
                    paneId: paneId,
                    tabId: tabId,
                    tabDisplayLabel: "Tab 2",
                    tabOrdinal: 2,
                    repoId: repoId,
                    repoName: "agent-studio",
                    worktreeId: worktreeId,
                    worktreeName: "sqlite",
                    branchName: "sqlite",
                    paneDisplayLabel: "Agent",
                    paneOrdinal: 3,
                    paneRole: .drawerChild,
                    parentPaneId: parentPaneId,
                    parentPaneDisplayLabel: "Terminal",
                    parentPaneOrdinal: 1,
                    drawerOrdinal: 4,
                    runtimeDisplayLabel: "zsh"
                )
            ),
            activityContext: .init(
                burstWindowId: burstWindowId,
                activitySessionId: activitySessionId,
                eventCount: 5,
                rowsAdded: 6,
                thresholdRows: 7,
                latestRows: 8
            ),
            claimKey: .init(
                paneId: paneId,
                lane: .activity,
                semantic: .unseenActivity,
                sessionId: claimSessionId
            )
        )
        let globalNotification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000022")!,
            timestamp: Date(timeIntervalSince1970: 1001),
            kind: .persistenceRecovery,
            title: "Workspace recovered",
            body: nil,
            source: .global,
            activityContext: nil,
            claimKey: nil,
            isRead: true,
            isDismissedFromPaneInbox: true
        )

        try fixture.repository.replaceAll([paneNotification, globalNotification])

        #expect(try fixture.repository.fetchNotifications() == [paneNotification, globalNotification])
        try assertNotificationRowColumns(
            databaseQueue: fixture.databaseQueue,
            workspaceId: workspaceId,
            notification: paneNotification
        )
        try assertGlobalNotificationRowColumns(
            databaseQueue: fixture.databaseQueue,
            workspaceId: workspaceId,
            notification: globalNotification
        )
    }

    @Test("collapsed inbox groups round trip without persisting pending filters")
    func collapsedInboxGroupsRoundTripWithoutPersistingPendingFilters() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let groups: Set<InboxNotificationGroupKey> = [
            InboxNotificationGroupKey("repo:agent-studio"),
            InboxNotificationGroupKey("pane:terminal"),
        ]

        try fixture.repository.replaceCollapsedGroups(groups)

        #expect(try fixture.repository.fetchCollapsedGroups() == groups)
    }

    @Test("empty inbox snapshots mark the SQLite lane as initialized")
    func emptyInboxSnapshotsMarkTheSQLiteLaneAsInitialized() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000009")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)

        #expect(try fixture.repository.hasPersistedState() == false)
        #expect(try fixture.repository.hasMaterializedLegacyImport() == false)

        try fixture.repository.replaceSnapshot(notifications: [], collapsedGroups: [])

        #expect(try fixture.repository.fetchNotifications().isEmpty)
        #expect(try fixture.repository.fetchCollapsedGroups().isEmpty)
        #expect(try fixture.repository.hasPersistedState())
        #expect(try fixture.repository.hasMaterializedLegacyImport() == false)
    }

    @Test("legacy import snapshots mark an archive-safe materialization proof")
    func legacyImportSnapshotsMarkArchiveSafeMaterializationProof() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000019")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)

        try fixture.repository.replaceLegacyImportSnapshot(notifications: [], collapsedGroups: [])

        #expect(try fixture.repository.hasPersistedState())
        #expect(try fixture.repository.hasMaterializedLegacyImport())
    }

    @Test("upsert by claim mirrors InboxNotificationAtom coalescence rules")
    func upsertByClaimMirrorsInboxNotificationAtomCoalescenceRules() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000003")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let claimFixture = makeClaimCoalescenceFixture()
        let atom = InboxNotificationAtom()
        atom.replaceAll(claimFixture.seedNotifications)
        try fixture.repository.replaceAll(claimFixture.seedNotifications)

        for notification in claimFixture.incomingNotifications {
            let atomOutcome = atom.upsertByClaim(notification, merge: promoterStyleMerge(existing:incoming:))
            let repositoryOutcome = try fixture.repository.upsertByClaim(
                notification,
                merge: promoterStyleMerge(existing:incoming:)
            )
            #expect(repositoryOutcome.notificationId == atomOutcome.notificationId)
            #expect(repositoryOutcome.didCoalesce == atomOutcome.didCoalesce)
            #expect(
                repositoryOutcome.retentionOutcome.droppedNotificationIds
                    == atomOutcome.retentionOutcome.droppedNotificationIds
            )
        }

        #expect(try fixture.repository.fetchNotifications() == atom.notifications)
    }

    @Test("migrated legacy storage tokens decode into current notification models")
    func migratedLegacyStorageTokensDecodeIntoCurrentNotificationModels() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000006")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let paneId = UUID(uuidString: "20000000-0000-0000-0000-000000000061")!
        let actionId = UUID(uuidString: "20000000-0000-0000-0000-000000000062")!
        let activityId = UUID(uuidString: "20000000-0000-0000-0000-000000000063")!

        try insertRawNotificationRow(
            databaseQueue: fixture.databaseQueue,
            row: RawNotificationRow(
                workspaceId: workspaceId,
                id: actionId,
                timestamp: 30,
                kind: "action",
                title: "Approval",
                sourceKind: "agent",
                paneId: paneId,
                paneRole: "terminal",
                claimPaneId: paneId,
                claimLane: "actionNeeded",
                claimSemantic: "approvalRequested"
            )
        )
        try insertRawNotificationRow(
            databaseQueue: fixture.databaseQueue,
            row: RawNotificationRow(
                workspaceId: workspaceId,
                id: activityId,
                timestamp: 31,
                kind: "activity",
                title: "Activity",
                sourceKind: "terminal",
                paneId: paneId,
                paneRole: "terminal",
                claimPaneId: paneId,
                claimLane: "activity",
                claimSemantic: "unseenActivity"
            )
        )

        let notifications = try fixture.repository.fetchNotifications()

        #expect(notifications.map(\.id) == [actionId, activityId])
        #expect(notifications[0].kind == .approvalRequested)
        #expect(notifications[0].source == .pane(.init(paneId: paneId, paneRole: .main)))
        #expect(notifications[0].claimKey?.semantic == .approvalRequested)
        #expect(notifications[1].kind == .unseenActivity)
        #expect(notifications[1].source == .pane(.init(paneId: paneId, paneRole: .main)))
        #expect(notifications[1].claimKey?.semantic == .unseenActivity)
    }

    @Test("upsert by claim prefers exact claim match before session fallback")
    func upsertByClaimPrefersExactClaimMatchBeforeSessionFallback() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000007")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let paneId = UUID(uuidString: "20000000-0000-0000-0000-000000000071")!
        let sessionId = UUID(uuidString: "20000000-0000-0000-0000-000000000072")!
        let olderSessionOnlyNotification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000073")!,
            timestamp: Date(timeIntervalSince1970: 40),
            kind: .unseenActivity,
            title: "Older session activity",
            source: .pane(.init(paneId: paneId)),
            claimKey: .init(
                paneId: paneId,
                lane: .activity,
                semantic: .unseenActivity,
                sessionId: sessionId
            )
        )
        let laterExactNotification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000074")!,
            timestamp: Date(timeIntervalSince1970: 41),
            kind: .approvalRequested,
            title: "Exact action",
            source: .pane(.init(paneId: paneId)),
            claimKey: .init(
                paneId: paneId,
                lane: .actionNeeded,
                semantic: .approvalRequested,
                sessionId: sessionId
            )
        )
        let incomingNotification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000075")!,
            timestamp: Date(timeIntervalSince1970: 42),
            kind: .approvalRequested,
            title: "Replacement action",
            source: .pane(.init(paneId: paneId)),
            claimKey: laterExactNotification.claimKey
        )
        try fixture.repository.replaceAll([olderSessionOnlyNotification, laterExactNotification])

        let repositoryOutcome = try fixture.repository.upsertByClaim(
            incomingNotification,
            merge: promoterStyleMerge(existing:incoming:)
        )
        let restoredNotifications = try fixture.repository.fetchNotifications()

        #expect(repositoryOutcome.notificationId == laterExactNotification.id)
        #expect(repositoryOutcome.didCoalesce)
        #expect(restoredNotifications.map(\.id) == [olderSessionOnlyNotification.id, laterExactNotification.id])
        #expect(restoredNotifications[1].title == incomingNotification.title)
    }

    @Test("retention cap deletes oldest overflow rows during append")
    func retentionCapDeletesOldestOverflowRowsDuringAppend() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000004")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let cap = AppPolicies.InboxNotification.maxRetained
        let seedNotifications = (0..<cap).map { index in
            makeRepositoryNotification(
                id: UUID(uuidString: "20000000-0000-0000-0000-\(String(format: "%012d", 100 + index))")!,
                timestamp: Date(timeIntervalSince1970: TimeInterval(index)),
                title: "Seed \(index)"
            )
        }
        let incomingNotification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000009999")!,
            timestamp: Date(timeIntervalSince1970: TimeInterval(cap + 1)),
            title: "Incoming"
        )
        try fixture.repository.replaceAll(seedNotifications)

        let outcome = try fixture.repository.append(incomingNotification)
        let restoredNotifications = try fixture.repository.fetchNotifications()
        let rowCount = try fixture.databaseQueue.read { database in
            try Int.fetchOne(
                database,
                sql: """
                    SELECT COUNT(*)
                    FROM local_notification_inbox_item
                    WHERE workspace_id = ?
                    """,
                arguments: [workspaceId.uuidString]
            )
        }

        #expect(outcome.droppedNotificationIds == [seedNotifications[0].id])
        #expect(restoredNotifications.count == cap)
        #expect(restoredNotifications.first?.id == seedNotifications[1].id)
        #expect(restoredNotifications.last?.id == incomingNotification.id)
        #expect(rowCount == cap)
    }

    @Test("retention cap deletes read activity before unread roll-up alerts")
    func retentionCapDeletesReadActivityBeforeUnreadRollUpAlerts() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000020")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let cap = AppPolicies.InboxNotification.maxRetained
        let base = Date(timeIntervalSince1970: 2_000_000)
        let unreadAlert = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000010001")!,
            timestamp: base,
            kind: .approvalRequested,
            title: "Old action",
            claimKey: .init(
                paneId: UUID(uuidString: "20000000-0000-0000-0000-000000010002")!,
                lane: .actionNeeded,
                semantic: .approvalRequested,
                sessionId: nil
            )
        )
        let readActivity = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000010003")!,
            timestamp: base.addingTimeInterval(1),
            kind: .unseenActivity,
            title: "Read activity",
            claimKey: .init(
                paneId: UUID(uuidString: "20000000-0000-0000-0000-000000010004")!,
                lane: .activity,
                semantic: .unseenActivity,
                sessionId: nil
            ),
            isRead: true,
            isDismissedFromPaneInbox: true
        )
        let activitySpam = (2..<cap).map { index in
            makeRepositoryNotification(
                id: UUID(uuidString: "20000000-0000-0000-0000-\(String(format: "%012d", 110_000 + index))")!,
                timestamp: base.addingTimeInterval(TimeInterval(index)),
                kind: .unseenActivity,
                title: "Activity \(index)",
                claimKey: .init(
                    paneId: UUID(),
                    lane: .activity,
                    semantic: .unseenActivity,
                    sessionId: nil
                )
            )
        }
        try fixture.repository.replaceAll([unreadAlert, readActivity] + activitySpam)

        let outcome = try fixture.repository.append(
            makeRepositoryNotification(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000019999")!,
                timestamp: base.addingTimeInterval(TimeInterval(cap + 1)),
                kind: .unseenActivity,
                title: "Incoming activity",
                claimKey: .init(
                    paneId: UUID(),
                    lane: .activity,
                    semantic: .unseenActivity,
                    sessionId: nil
                )
            )
        )
        let restoredNotifications = try fixture.repository.fetchNotifications()

        #expect(outcome.droppedNotificationIds == [readActivity.id])
        #expect(restoredNotifications.contains(where: { $0.id == unreadAlert.id }))
        #expect(restoredNotifications.contains(where: { $0.id == readActivity.id }) == false)
    }

    @Test("retention cap deletes overflow rows with one batch statement")
    func retentionCapDeletesOverflowRowsWithOneBatchStatement() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000074")!
        let recorder = SQLStatementRecorder()
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(
            workspaceId: workspaceId,
            statementRecorder: recorder
        )
        let cap = AppPolicies.InboxNotification.maxRetained
        for index in 0..<(cap + 2) {
            try insertRawNotificationRow(
                databaseQueue: fixture.databaseQueue,
                row: .init(
                    workspaceId: workspaceId,
                    id: UUID(uuidString: "20000000-0000-0000-0000-\(String(format: "%012d", 200 + index))")!,
                    timestamp: TimeInterval(index),
                    kind: InboxNotificationKind.agentDesktopNotification.rawValue,
                    title: "Seed \(index)",
                    sourceKind: "global"
                )
            )
        }
        let incomingNotification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000008888")!,
            timestamp: Date(timeIntervalSince1970: TimeInterval(cap + 3)),
            title: "Incoming"
        )
        recorder.reset()

        let outcome = try fixture.repository.append(incomingNotification)
        let deleteStatements = recorder.statements().filter {
            $0
                .replacingOccurrences(of: "\n", with: " ")
                .lowercased()
                .contains("delete from local_notification_inbox_item")
        }

        #expect(outcome.droppedNotificationIds.count == 3)
        #expect(deleteStatements.count == 1)
    }

    @Test("read dismiss and clear mutations update persisted rows")
    func readDismissAndClearMutationsUpdatePersistedRows() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000005")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let paneId = UUID(uuidString: "20000000-0000-0000-0000-000000000051")!
        let readNotification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000052")!,
            timestamp: Date(timeIntervalSince1970: 10),
            title: "Read me",
            source: .pane(.init(paneId: paneId))
        )
        let paneNotification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000053")!,
            timestamp: Date(timeIntervalSince1970: 11),
            title: "Dismiss me",
            source: .pane(.init(paneId: paneId))
        )
        let otherNotification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000054")!,
            timestamp: Date(timeIntervalSince1970: 12),
            title: "Keep me"
        )
        try fixture.repository.replaceAll([readNotification, paneNotification, otherNotification])

        #expect(try fixture.repository.markRead(id: readNotification.id))
        try fixture.repository.dismissFromPaneInbox(paneId: paneId)
        try fixture.repository.clearReadHistory()

        let restoredNotifications = try fixture.repository.fetchNotifications()
        #expect(restoredNotifications.map(\InboxNotification.id) == [paneNotification.id, otherNotification.id])
        #expect(restoredNotifications.first?.isDismissedFromPaneInbox == true)
        #expect(restoredNotifications.last?.isRead == false)
    }

    @Test("toggle read state clears pane dismissal when reopening unread")
    func toggleReadStateClearsPaneDismissalWhenReopeningUnread() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000010")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let paneId = UUID(uuidString: "20000000-0000-0000-0000-000000000101")!
        let notification = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000102")!,
            timestamp: Date(timeIntervalSince1970: 10),
            title: "Reopen me",
            source: .pane(.init(paneId: paneId)),
            isRead: true,
            isDismissedFromPaneInbox: true
        )
        try fixture.repository.replaceAll([notification])

        #expect(try fixture.repository.toggleReadState(id: notification.id))

        let restoredNotifications = try fixture.repository.fetchNotifications()
        #expect(restoredNotifications.count == 1)
        #expect(restoredNotifications[0].isRead == false)
        #expect(restoredNotifications[0].isDismissedFromPaneInbox == false)
    }

    @Test("markRead(scope:) persists repo, worktree, and pane scoped reads")
    func markReadByScopePersistsScopedReads() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000011")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let repoId = UUID(uuidString: "20000000-0000-0000-0000-000000000111")!
        let worktreeId = UUID(uuidString: "20000000-0000-0000-0000-000000000112")!
        let paneA = UUID(uuidString: "20000000-0000-0000-0000-000000000113")!
        let paneB = UUID(uuidString: "20000000-0000-0000-0000-000000000114")!
        let notifications = [
            makeRepositoryNotification(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000115")!,
                timestamp: Date(timeIntervalSince1970: 10),
                source: .pane(.init(paneId: paneA, repoId: repoId))
            ),
            makeRepositoryNotification(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000116")!,
                timestamp: Date(timeIntervalSince1970: 11),
                source: .pane(.init(paneId: paneB, worktreeId: worktreeId))
            ),
            makeRepositoryNotification(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000117")!,
                timestamp: Date(timeIntervalSince1970: 12),
                source: .pane(.init(paneId: paneB))
            ),
            makeRepositoryNotification(
                id: UUID(uuidString: "20000000-0000-0000-0000-000000000118")!,
                timestamp: Date(timeIntervalSince1970: 13)
            ),
        ]
        try fixture.repository.replaceAll(notifications)

        try fixture.repository.markRead(scope: .repo(repoId))
        #expect(try fixture.repository.fetchNotifications().map(\.isRead) == [true, false, false, false])

        try fixture.repository.markRead(scope: .worktree(worktreeId))
        #expect(try fixture.repository.fetchNotifications().map(\.isRead) == [true, true, false, false])

        try fixture.repository.markRead(scope: .paneIds([paneB]))
        #expect(try fixture.repository.fetchNotifications().map(\.isRead) == [true, true, true, false])
    }

    @Test("upsert by claim reopens read activity history for stronger lane")
    func upsertByClaimReopensReadActivityHistoryForStrongerLane() throws {
        let workspaceId = UUID(uuidString: "20000000-0000-0000-0000-000000000021")!
        let fixture = try makeInboxNotificationSQLiteRepositoryFixture(workspaceId: workspaceId)
        let paneId = UUID(uuidString: "20000000-0000-0000-0000-000000000211")!
        let sessionId = UUID(uuidString: "20000000-0000-0000-0000-000000000212")!
        let existingActivity = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000213")!,
            timestamp: Date(timeIntervalSince1970: 10),
            kind: .unseenActivity,
            title: "Observed activity",
            source: .pane(.init(paneId: paneId)),
            claimKey: .init(
                paneId: paneId,
                lane: .activity,
                semantic: .unseenActivity,
                sessionId: sessionId
            ),
            isRead: true,
            isDismissedFromPaneInbox: false
        )
        let incomingAction = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000214")!,
            timestamp: Date(timeIntervalSince1970: 11),
            kind: .approvalRequested,
            title: "Approval required",
            source: .pane(.init(paneId: paneId)),
            claimKey: .init(
                paneId: paneId,
                lane: .actionNeeded,
                semantic: .approvalRequested,
                sessionId: sessionId
            )
        )
        try fixture.repository.replaceAll([existingActivity])

        let outcome = try fixture.repository.upsertByClaim(
            incomingAction,
            merge: promoterStyleMerge(existing:incoming:)
        )
        let restoredNotifications = try fixture.repository.fetchNotifications()

        #expect(outcome.notificationId == existingActivity.id)
        #expect(outcome.didCoalesce)
        #expect(restoredNotifications.count == 1)
        #expect(restoredNotifications[0].kind == .approvalRequested)
        #expect(restoredNotifications[0].claimKey?.lane == .actionNeeded)
        #expect(restoredNotifications[0].isRead == false)
        #expect(restoredNotifications[0].isDismissedFromPaneInbox == false)

        let incomingSafety = makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000215")!,
            timestamp: Date(timeIntervalSince1970: 12),
            kind: .terminalRendererUnhealthy,
            title: "Terminal renderer unhealthy",
            source: .pane(.init(paneId: paneId)),
            claimKey: .init(
                paneId: paneId,
                lane: .safety,
                semantic: .rendererUnhealthy,
                sessionId: sessionId
            )
        )
        try fixture.repository.replaceAll([existingActivity])

        let safetyOutcome = try fixture.repository.upsertByClaim(
            incomingSafety,
            merge: promoterStyleMerge(existing:incoming:)
        )
        let restoredSafetyNotifications = try fixture.repository.fetchNotifications()

        #expect(safetyOutcome.notificationId == existingActivity.id)
        #expect(safetyOutcome.didCoalesce)
        #expect(restoredSafetyNotifications.count == 1)
        #expect(restoredSafetyNotifications[0].kind == .terminalRendererUnhealthy)
        #expect(restoredSafetyNotifications[0].claimKey?.lane == .safety)
        #expect(restoredSafetyNotifications[0].isRead == false)
        #expect(restoredSafetyNotifications[0].isDismissedFromPaneInbox == false)
    }
}

struct InboxNotificationSQLiteRepositoryFixture {
    let repository: InboxNotificationSQLiteRepository
    let databaseQueue: DatabaseQueue
}

final class SQLStatementRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStatements: [String] = []

    func record(_ statement: String) {
        lock.lock()
        defer { lock.unlock() }
        recordedStatements.append(statement)
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        recordedStatements.removeAll()
    }

    func statements() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return recordedStatements
    }
}

func makeInboxNotificationSQLiteRepositoryFixture(
    workspaceId: UUID,
    statementRecorder: SQLStatementRecorder? = nil
) throws -> InboxNotificationSQLiteRepositoryFixture {
    var configuration = SQLiteDatabaseFactory.makeConfiguration(label: "AgentStudio.sqlite.inbox-test")
    if let statementRecorder {
        configuration.prepareDatabase { database in
            database.trace { event in
                statementRecorder.record("\(event)")
            }
        }
    }
    let databaseQueue = try DatabaseQueue(named: nil, configuration: configuration)
    try WorkspaceLocalMigrations.migrate(databaseQueue)
    return .init(
        repository: InboxNotificationSQLiteRepository(workspaceId: workspaceId, databaseWriter: databaseQueue),
        databaseQueue: databaseQueue
    )
}

private func makeRepositoryNotification(
    id: UUID = UUID(),
    timestamp: Date = Date(timeIntervalSince1970: 1),
    kind: InboxNotificationKind = .agentDesktopNotification,
    title: String = "Notification",
    body: String? = nil,
    source: InboxNotification.Source = .global,
    activityContext: InboxNotification.ActivityContext? = nil,
    claimKey: InboxNotificationClaimKey? = nil,
    isRead: Bool = false,
    isDismissedFromPaneInbox: Bool = false
) -> InboxNotification {
    InboxNotification(
        id: id,
        timestamp: timestamp,
        kind: kind,
        title: title,
        body: body,
        source: source,
        activityContext: activityContext,
        claimKey: claimKey,
        isRead: isRead,
        isDismissedFromPaneInbox: isDismissedFromPaneInbox
    )
}

private struct ClaimCoalescenceFixture {
    let seedNotifications: [InboxNotification]
    let incomingNotifications: [InboxNotification]
}

private func makeClaimCoalescenceFixture() -> ClaimCoalescenceFixture {
    let paneId = UUID(uuidString: "20000000-0000-0000-0000-000000000031")!
    let sessionId = UUID(uuidString: "20000000-0000-0000-0000-000000000032")!
    let observedHistorySessionId = UUID(uuidString: "20000000-0000-0000-0000-000000000036")!
    let observedHistoryClaimKey = InboxNotificationClaimKey(
        paneId: paneId,
        lane: .activity,
        semantic: .bell,
        sessionId: observedHistorySessionId
    )
    let seedNotifications = makeClaimSeedNotifications(
        paneId: paneId,
        sessionId: sessionId,
        observedHistoryClaimKey: observedHistoryClaimKey
    )
    return .init(
        seedNotifications: seedNotifications,
        incomingNotifications: makeIncomingClaimNotifications(
            paneId: paneId,
            sessionId: sessionId,
            observedHistoryClaimKey: observedHistoryClaimKey
        )
    )
}

private func makeClaimSeedNotifications(
    paneId: UUID,
    sessionId: UUID,
    observedHistoryClaimKey: InboxNotificationClaimKey
) -> [InboxNotification] {
    [
        makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000033")!,
            timestamp: Date(timeIntervalSince1970: 10),
            kind: .unseenActivity,
            title: "Activity",
            source: .pane(.init(paneId: paneId)),
            claimKey: .init(
                paneId: paneId,
                lane: .activity,
                semantic: .unseenActivity,
                sessionId: sessionId
            )
        ),
        makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000034")!,
            timestamp: Date(timeIntervalSince1970: 11),
            kind: .securityEvent,
            title: "Safety",
            source: .pane(.init(paneId: paneId)),
            claimKey: .init(
                paneId: paneId,
                lane: .safety,
                semantic: .securityEvent,
                sessionId: nil
            )
        ),
        makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000035")!,
            timestamp: Date(timeIntervalSince1970: 12),
            kind: .bellRang,
            title: "Observed history",
            source: .pane(.init(paneId: paneId)),
            claimKey: observedHistoryClaimKey,
            isRead: true,
            isDismissedFromPaneInbox: true
        ),
    ]
}

private func makeIncomingClaimNotifications(
    paneId: UUID,
    sessionId: UUID,
    observedHistoryClaimKey: InboxNotificationClaimKey
) -> [InboxNotification] {
    [
        makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000041")!,
            timestamp: Date(timeIntervalSince1970: 20),
            kind: .approvalRequested,
            title: "Action needed",
            source: .pane(.init(paneId: paneId)),
            claimKey: .init(
                paneId: paneId,
                lane: .actionNeeded,
                semantic: .approvalRequested,
                sessionId: sessionId
            )
        ),
        makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000042")!,
            timestamp: Date(timeIntervalSince1970: 21),
            kind: .securityEvent,
            title: "Second safety",
            source: .pane(.init(paneId: paneId)),
            claimKey: .init(
                paneId: paneId,
                lane: .safety,
                semantic: .securityEvent,
                sessionId: nil
            )
        ),
        makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000043")!,
            timestamp: Date(timeIntervalSince1970: 22),
            kind: .bellRang,
            title: "Unread should not merge into observed history",
            source: .pane(.init(paneId: paneId)),
            claimKey: observedHistoryClaimKey
        ),
        makeRepositoryNotification(
            id: UUID(uuidString: "20000000-0000-0000-0000-000000000044")!,
            timestamp: Date(timeIntervalSince1970: 23),
            kind: .bellRang,
            title: "Read history can merge",
            source: .pane(.init(paneId: paneId)),
            claimKey: observedHistoryClaimKey,
            isRead: true,
            isDismissedFromPaneInbox: true
        ),
    ]
}

private func promoterStyleMerge(
    existing: InboxNotification,
    incoming: InboxNotification
) -> InboxNotification {
    let incomingIsMoreSpecific = claimLanePriority(incoming.claimKey?.lane) < claimLanePriority(existing.claimKey?.lane)
    let incomingIsSameClaim = existing.claimKey == incoming.claimKey
    let displaySource = incomingIsMoreSpecific || incomingIsSameClaim ? incoming : existing
    let shouldReopenReadRow =
        existing.isRead
        && !incoming.isRead
        && incomingIsMoreSpecific
    return InboxNotification(
        id: existing.id,
        timestamp: incoming.timestamp,
        kind: displaySource.kind,
        title: displaySource.title,
        body: displaySource.body,
        source: displaySource.source,
        activityContext: incoming.activityContext ?? existing.activityContext,
        claimKey: strongerClaimKey(existing: existing.claimKey, incoming: incoming.claimKey),
        isRead: shouldReopenReadRow ? false : existing.isRead || incoming.isRead,
        isDismissedFromPaneInbox: shouldReopenReadRow
            ? false
            : existing.isDismissedFromPaneInbox || incoming.isDismissedFromPaneInbox
    )
}

private func strongerClaimKey(
    existing: InboxNotificationClaimKey?,
    incoming: InboxNotificationClaimKey?
) -> InboxNotificationClaimKey? {
    guard let existing else { return incoming }
    guard let incoming else { return existing }
    return claimLanePriority(incoming.lane) < claimLanePriority(existing.lane) ? incoming : existing
}

private func claimLanePriority(_ lane: InboxNotificationClaimLane?) -> Int {
    switch lane {
    case .actionNeeded:
        return 0
    case .safety:
        return 1
    case .settledAgent:
        return 2
    case .activity:
        return 3
    case nil:
        return 4
    }
}

private func assertNotificationRowColumns(
    databaseQueue: DatabaseQueue,
    workspaceId: UUID,
    notification: InboxNotification
) throws {
    let row = try fetchNotificationRow(databaseQueue: databaseQueue, notificationId: notification.id)
    #expect(row["workspace_id"] as String? == workspaceId.uuidString)
    #expect(row["timestamp"] as Double? == notification.timestamp.timeIntervalSince1970)
    #expect(row["kind"] as String? == notification.kind.rawValue)
    #expect(row["title"] as String? == notification.title)
    #expect(row["body"] as String? == notification.body)
    #expect(row["source_kind"] as String? == "pane")
    #expect(row["pane_id"] as String? == notification.paneId?.uuidString)
    #expect(row["tab_id"] as String? == notification.tabId?.uuidString)
    #expect(row["tab_display_label"] as String? == "Tab 2")
    #expect(row["tab_ordinal"] as Int? == 2)
    #expect(row["repo_id"] as String? == notification.repoId?.uuidString)
    #expect(row["repo_name"] as String? == notification.repoName)
    #expect(row["worktree_id"] as String? == notification.worktreeId?.uuidString)
    #expect(row["worktree_name"] as String? == notification.worktreeName)
    #expect(row["branch_name"] as String? == notification.branchName)
    #expect(row["pane_display_label"] as String? == "Agent")
    #expect(row["pane_ordinal"] as Int? == 3)
    #expect(row["pane_role"] as String? == InboxNotification.PaneSource.PaneRole.drawerChild.rawValue)
    #expect(row["parent_pane_id"] as String? == "20000000-0000-0000-0000-000000000015")
    #expect(row["parent_pane_display_label"] as String? == "Terminal")
    #expect(row["parent_pane_ordinal"] as Int? == 1)
    #expect(row["drawer_ordinal"] as Int? == 4)
    #expect(row["runtime_display_label"] as String? == "zsh")
    #expect(row["activity_burst_window_id"] as String? == notification.activityContext?.burstWindowId.uuidString)
    #expect(row["activity_session_id"] as String? == notification.activityContext?.activitySessionId?.uuidString)
    #expect(row["activity_event_count"] as Int? == 5)
    #expect(row["activity_rows_added"] as Int? == 6)
    #expect(row["activity_threshold_rows"] as Int? == 7)
    #expect(row["activity_latest_rows"] as Int? == 8)
    #expect(row["claim_pane_id"] as String? == notification.claimKey?.paneId.uuidString)
    #expect(row["claim_lane"] as String? == notification.claimKey?.lane.rawValue)
    #expect(row["claim_semantic"] as String? == notification.claimKey?.semantic.rawValue)
    #expect(row["claim_session_id"] as String? == notification.claimKey?.sessionId?.uuidString)
    #expect(row["is_read"] as Int? == 0)
    #expect(row["is_dismissed_from_pane_inbox"] as Int? == 0)
}

private func assertGlobalNotificationRowColumns(
    databaseQueue: DatabaseQueue,
    workspaceId: UUID,
    notification: InboxNotification
) throws {
    let row = try fetchNotificationRow(databaseQueue: databaseQueue, notificationId: notification.id)
    #expect(row["workspace_id"] as String? == workspaceId.uuidString)
    #expect(row["source_kind"] as String? == "global")
    #expect(row["pane_id"] as String? == nil)
    #expect(row["claim_pane_id"] as String? == nil)
    #expect(row["is_read"] as Int? == 1)
    #expect(row["is_dismissed_from_pane_inbox"] as Int? == 1)
}

private func fetchNotificationRow(
    databaseQueue: DatabaseQueue,
    notificationId: UUID
) throws -> Row {
    try databaseQueue.read { database in
        let row = try Row.fetchOne(
            database,
            sql: """
                SELECT *
                FROM local_notification_inbox_item
                WHERE id = ?
                """,
            arguments: [notificationId.uuidString]
        )
        return try #require(row)
    }
}
