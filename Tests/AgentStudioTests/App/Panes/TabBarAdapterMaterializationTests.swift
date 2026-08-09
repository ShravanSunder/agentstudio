import Foundation
import Observation
import Synchronization
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite(.serialized)
final class TabBarAdapterMaterializationTests {

    private var store: WorkspaceStore!
    private var repoCache: RepoCacheAtom!
    private var inboxAtom: InboxNotificationAtom!
    private var adapter: TabBarAdapter!

    init() {
        installTestCoreAtomsIfNeeded()
        store = WorkspaceStore()
        repoCache = RepoCacheAtom()
        inboxAtom = InboxNotificationAtom()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom
        )
    }

    deinit {
        adapter = nil
        inboxAtom = nil
        store = nil
        repoCache = nil
    }

    @Test("first materialization exposes no authoritative items or active selection")
    func firstMaterializationHasNoAuthoritativeOutput() async throws {
        let projectionGate = TabBarAdapterProjectionGate()
        defer { projectionGate.release() }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: projectionGate]
        )
        let pane = store.createPane(title: "Held")
        let tab = Tab(paneId: pane.id, name: "Held")
        store.appendTab(tab)
        adapter.stop()

        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project
        )
        let didStart = await projectionGate.waitUntilStarted()

        #expect(didStart, "Initial projection did not start")
        #expect(adapter.tabs.isEmpty)
        #expect(adapter.activeTabId == nil)
    }

    @Test("one materialized projection publishes coherent items and active identity")
    func materializedProjectionPublishesItemsAndActiveIdentityCoherently() async throws {
        let projectionGate = TabBarAdapterProjectionGate()
        defer { projectionGate.release() }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: projectionGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Coherent")
        let tab = Tab(paneId: pane.id, name: "Coherent")
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        let didStart = await projectionGate.waitUntilStarted()
        #expect(didStart, "Initial projection did not start")

        projectionGate.release()
        let didPublish = await completionRecorder.wait(for: .published(.init(value: 1)))

        #expect(didPublish, "Initial coherent projection did not publish")
        #expect(adapter.tabs.map(\.id) == [tab.id])
        #expect(adapter.activeTabId == tab.id)
    }

    @Test("equal and unrelated source changes do not republish tab output")
    func equalAndUnrelatedSourceChangesDoNotRepublishOutput() async {
        let projectionController = TabBarAdapterProjectionController(returnsFirstProjection: true)
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Stable")
        let tab = Tab(paneId: pane.id, name: "Stable")
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await completionRecorder.wait(for: .published(.init(value: 1))))
        #expect(await waitUntil { self.adapter.outputPublicationRevision == 1 })
        let publicationRevisionAfterInitialOutput = adapter.outputPublicationRevision
        #expect(publicationRevisionAfterInitialOutput == 1)
        let outputObservationCount = TabBarAdapterTestCounter()
        withObservationTracking {
            _ = adapter.tabs
        } onChange: {
            outputObservationCount.increment()
        }

        store.renameTab(tab.id, name: "Changed source with equal projected output")
        #expect(await completionRecorder.wait(for: .equal(.init(value: 2))))

        let projectionCountAfterEqualOutput = projectionController.projectionCount
        let managementLayerChanged = TabBarAdapterTestSignal()
        withObservationTracking {
            _ = adapter.isManagementLayerActive
        } onChange: {
            managementLayerChanged.signal()
        }
        atom(\.managementLayer).activate()
        #expect(await managementLayerChanged.wait(), "Management-layer observation did not update")

        #expect(adapter.materializedProjection(for: tab.id)?.revision == 0)
        #expect(adapter.outputPublicationRevision == publicationRevisionAfterInitialOutput)
        #expect(!outputObservationCount.didIncrement)
        #expect(projectionController.projectionCount == projectionCountAfterEqualOutput)
    }

    @Test("leading-edge invalidation revokes held work before successor admission")
    func leadingEdgeInvalidationRevokesHeldWorkBeforeSuccessorAdmission() async {
        let firstGate = TabBarAdapterProjectionGate()
        let successorGate = TabBarAdapterProjectionGate()
        defer {
            firstGate.release()
            successorGate.release()
        }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: firstGate, 2: successorGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Before")
        let tab = Tab(paneId: pane.id, name: "Before")
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await firstGate.waitUntilStarted(), "First projection did not start")

        store.renameTab(tab.id, name: "After")
        firstGate.release()
        #expect(await completionRecorder.wait(for: .superseded(.init(value: 1))))
        #expect(adapter.materializedProjection(for: tab.id)?.value == nil)
        #expect(await successorGate.waitUntilStarted(), "Successor projection did not start")

        successorGate.release()
        #expect(await completionRecorder.wait(for: .published(.init(value: 2))))
        #expect(adapter.tabs.first?.displayTitle == "After")
    }

    @Test("overlapping projections publish only the latest admitted request")
    func overlappingProjectionsPublishOnlyLatestRequest() async {
        let secondGate = TabBarAdapterProjectionGate()
        let thirdGate = TabBarAdapterProjectionGate()
        defer {
            secondGate.release()
            thirdGate.release()
        }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [2: secondGate, 3: thirdGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Initial")
        let tab = Tab(paneId: pane.id, name: "Initial")
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await completionRecorder.wait(for: .published(.init(value: 1))))

        store.renameTab(tab.id, name: "Superseded")
        #expect(await secondGate.waitUntilStarted(), "Second projection did not start")
        store.renameTab(tab.id, name: "Latest")
        secondGate.release()
        #expect(await completionRecorder.wait(for: .superseded(.init(value: 2))))
        #expect(await thirdGate.waitUntilStarted(), "Third projection did not start")

        thirdGate.release()
        #expect(await completionRecorder.wait(for: .published(.init(value: 3))))
        #expect(adapter.tabs.first?.displayTitle == "Latest")
        #expect(projectionController.projectedGenerations == [1, 2, 3])
    }

    @Test("pane title mutation projects only the tab containing that pane")
    func paneTitleMutationProjectsOnlyOwningTab() async throws {
        let projectionController = TabBarAdapterProjectionController()
        let firstPane = store.createPane(title: "First")
        let secondPane = store.createPane(title: "Second")
        let firstTab = Tab(paneId: firstPane.id)
        let secondTab = Tab(paneId: secondPane.id)
        store.appendTab(firstTab)
        store.appendTab(secondTab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project
        )
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.id) == [firstTab.id, secondTab.id]
            },
            "Initial tab projection did not publish"
        )
        let initialProjectionCount = projectionController.projectionCount

        store.updatePaneTitle(firstPane.id, title: "First renamed")

        #expect(
            await waitForOutput {
                self.adapter.tabs.first { $0.id == firstTab.id }?.title == "First renamed"
            },
            "Owning tab did not publish its renamed pane title"
        )
        #expect(projectionController.projectionCount == initialProjectionCount + 1)
        #expect(Array(projectionController.projectedTabIDs.suffix(1)) == [firstTab.id])
    }

    @Test("keyed inbox mutation projects only the tab containing that pane")
    func keyedInboxMutationProjectsOnlyOwningTab() async {
        let projectionController = TabBarAdapterProjectionController()
        let firstPane = store.createPane(title: "First")
        let secondPane = store.createPane(title: "Second")
        let firstTab = Tab(paneId: firstPane.id)
        let secondTab = Tab(paneId: secondPane.id)
        store.appendTab(firstTab)
        store.appendTab(secondTab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project
        )
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.id) == [firstTab.id, secondTab.id]
            },
            "Initial tab projection did not publish"
        )
        let initialProjectionCount = projectionController.projectionCount

        inboxAtom.append(
            InboxNotification(
                id: UUIDv7.generate(),
                timestamp: Date(timeIntervalSince1970: 100),
                kind: .approvalRequested,
                title: "Approval requested",
                body: nil,
                source: .pane(.init(paneId: firstPane.id)),
                claimKey: .init(
                    paneId: firstPane.id,
                    lane: .actionNeeded,
                    semantic: .approvalRequested,
                    sessionId: nil
                ),
                isRead: false,
                isDismissedFromPaneInbox: false
            )
        )

        #expect(
            await waitForOutput {
                self.adapter.tabs.first { $0.id == firstTab.id }?.notificationDotColor == .red
            },
            "Owning tab did not publish its keyed inbox attention"
        )
        #expect(projectionController.projectionCount == initialProjectionCount + 1)
        #expect(Array(projectionController.projectedTabIDs.suffix(1)) == [firstTab.id])
    }

    @Test("appending a tab projects only the new tab item")
    func appendingTabProjectsOnlyNewTabItem() async {
        let projectionController = TabBarAdapterProjectionController()
        let firstPane = store.createPane(title: "First")
        let secondPane = store.createPane(title: "Second")
        let firstTab = Tab(paneId: firstPane.id)
        let secondTab = Tab(paneId: secondPane.id)
        store.appendTab(firstTab)
        store.appendTab(secondTab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project
        )
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.id) == [firstTab.id, secondTab.id]
            },
            "Initial aggregate did not publish"
        )
        let initialProjectionCount = projectionController.projectionCount

        let appendedPane = store.createPane(title: "Appended")
        let appendedTab = Tab(paneId: appendedPane.id)
        store.appendTab(appendedTab)

        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.id) == [firstTab.id, secondTab.id, appendedTab.id]
            },
            "Appended tab did not join the aggregate"
        )
        #expect(projectionController.projectionCount == initialProjectionCount + 1)
        #expect(Array(projectionController.projectedTabIDs.suffix(1)) == [appendedTab.id])
    }

    @Test("reordering tabs reuses materialized items without reprojection")
    func reorderingTabsReusesMaterializedItemsWithoutReprojection() async {
        let projectionController = TabBarAdapterProjectionController()
        let firstPane = store.createPane(title: "First")
        let secondPane = store.createPane(title: "Second")
        let thirdPane = store.createPane(title: "Third")
        let firstTab = Tab(paneId: firstPane.id)
        let secondTab = Tab(paneId: secondPane.id)
        let thirdTab = Tab(paneId: thirdPane.id)
        store.appendTab(firstTab)
        store.appendTab(secondTab)
        store.appendTab(thirdTab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project
        )
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.id) == [firstTab.id, secondTab.id, thirdTab.id]
            },
            "Initial aggregate did not publish"
        )
        let initialProjectionCount = projectionController.projectionCount

        store.moveTab(fromId: thirdTab.id, toIndex: 0)

        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.id) == [thirdTab.id, firstTab.id, secondTab.id]
            },
            "Reordered aggregate did not publish"
        )
        #expect(projectionController.projectionCount == initialProjectionCount)
    }

    @Test("removed held tab cannot publish after its worker is released")
    func removedHeldTabCannotPublishAfterRelease() async throws {
        let projectionGate = TabBarAdapterProjectionGate()
        defer { projectionGate.release() }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: projectionGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Removed while projecting")
        let tab = Tab(paneId: pane.id)
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await projectionGate.waitUntilStarted(), "Held tab projection did not start")
        let retainedProjection = try #require(adapter.materializedProjection(for: tab.id))
        let stoppedProjectionWaiter = TabBarAdapterConditionWaiter {
            retainedProjection.freshness == .stopped
        }

        store.removeTab(tab.id)

        #expect(
            await stoppedProjectionWaiter.wait(),
            "Removed tab projection did not stop"
        )
        #expect(adapter.materializedProjection(for: tab.id) == nil)
        let revisionAfterRemoval = adapter.outputPublicationRevision
        projectionGate.release()
        #expect(await completionRecorder.wait(for: .cancelled(.init(value: 1))))

        #expect(retainedProjection.freshness == .stopped)
        #expect(adapter.tabs.isEmpty)
        #expect(adapter.activeTabId == nil)
        #expect(adapter.outputPublicationRevision == revisionAfterRemoval)
    }

    @Test("new tabs completing out of order never publish a partial list")
    func newTabsCompletingOutOfOrderNeverPublishPartialList() async {
        let firstGate = TabBarAdapterProjectionGate()
        let secondGate = TabBarAdapterProjectionGate()
        defer {
            firstGate.release()
            secondGate.release()
        }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: firstGate, 2: secondGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let firstPane = store.createPane(title: "First")
        let secondPane = store.createPane(title: "Second")
        let firstTab = Tab(paneId: firstPane.id)
        let secondTab = Tab(paneId: secondPane.id)
        store.appendTab(firstTab)
        store.appendTab(secondTab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await firstGate.waitUntilStarted(), "First tab projection did not start")
        #expect(await secondGate.waitUntilStarted(), "Second tab projection did not start")

        secondGate.release()
        #expect(await completionRecorder.wait(for: .published(.init(value: 2))))
        #expect(adapter.tabs.isEmpty)
        #expect(adapter.activeTabId == nil)

        firstGate.release()
        #expect(await completionRecorder.wait(for: .published(.init(value: 1))))
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.id) == [firstTab.id, secondTab.id]
                    && self.adapter.activeTabId == secondTab.id
            },
            "Coherent aggregate did not publish after both tab items became current"
        )
    }

    @Test("retained tabs completing out of order never publish mixed generations")
    func retainedTabsCompletingOutOfOrderNeverPublishMixedGenerations() async {
        let firstRefreshGate = TabBarAdapterProjectionGate()
        let secondRefreshGate = TabBarAdapterProjectionGate()
        defer {
            firstRefreshGate.release()
            secondRefreshGate.release()
        }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [3: firstRefreshGate, 4: secondRefreshGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let firstPane = store.createPane(title: "First pane")
        let secondPane = store.createPane(title: "Second pane")
        let firstTab = Tab(paneId: firstPane.id, name: "First before")
        let secondTab = Tab(paneId: secondPane.id, name: "Second before")
        store.appendTab(firstTab)
        store.appendTab(secondTab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.displayTitle) == ["First before", "Second before"]
            },
            "Initial aggregate did not publish"
        )

        store.renameTab(firstTab.id, name: "First after")
        store.renameTab(secondTab.id, name: "Second after")
        #expect(await firstRefreshGate.waitUntilStarted(), "First refresh did not start")
        #expect(await secondRefreshGate.waitUntilStarted(), "Second refresh did not start")

        firstRefreshGate.release()
        #expect(await completionRecorder.wait(for: .published(.init(value: 3))))
        #expect(
            adapter.tabs.map(\.displayTitle) == ["First before", "Second before"],
            "A current item was published beside a stale retained item"
        )

        secondRefreshGate.release()
        #expect(await completionRecorder.wait(for: .published(.init(value: 4))))
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.displayTitle) == ["First after", "Second after"]
            },
            "The complete current generation did not publish"
        )
    }

    @Test("equal retained completion satisfies the current-generation publication barrier")
    func equalRetainedCompletionSatisfiesCurrentGenerationBarrier() async {
        let equalRefreshGate = TabBarAdapterProjectionGate()
        let changedRefreshGate = TabBarAdapterProjectionGate()
        defer {
            equalRefreshGate.release()
            changedRefreshGate.release()
        }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [3: equalRefreshGate, 4: changedRefreshGate],
            returnsFirstProjectionForGenerations: [3]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let firstPane = store.createPane(title: "First pane")
        let secondPane = store.createPane(title: "Second pane")
        let firstTab = Tab(paneId: firstPane.id, name: "First before")
        let secondTab = Tab(paneId: secondPane.id, name: "Second before")
        store.appendTab(firstTab)
        store.appendTab(secondTab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.displayTitle) == ["First before", "Second before"]
            },
            "Initial aggregate did not publish"
        )

        store.renameTab(firstTab.id, name: "First source changed")
        store.renameTab(secondTab.id, name: "Second after")
        #expect(await equalRefreshGate.waitUntilStarted(), "Equal refresh did not start")
        #expect(await changedRefreshGate.waitUntilStarted(), "Changed refresh did not start")

        changedRefreshGate.release()
        #expect(await completionRecorder.wait(for: .published(.init(value: 4))))
        #expect(adapter.tabs.map(\.displayTitle) == ["First before", "Second before"])

        equalRefreshGate.release()
        #expect(await completionRecorder.wait(for: .equal(.init(value: 3))))
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.displayTitle) == ["First before", "Second after"]
            },
            "Equal current-generation completion did not release the coherent aggregate"
        )
    }

    @Test("selected new tab retains the previous aggregate until its item is ready")
    func selectedNewTabRetainsPreviousAggregateUntilReady() async {
        let newTabGate = TabBarAdapterProjectionGate()
        defer { newTabGate.release() }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [2: newTabGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let existingPane = store.createPane(title: "Existing")
        let existingTab = Tab(paneId: existingPane.id)
        store.appendTab(existingTab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.id) == [existingTab.id]
                    && self.adapter.activeTabId == existingTab.id
            },
            "Existing aggregate did not publish"
        )

        let newPane = store.createPane(title: "New selected")
        let newTab = Tab(paneId: newPane.id)
        store.appendTab(newTab)
        store.setActiveTab(newTab.id)
        #expect(await newTabGate.waitUntilStarted(), "Selected new tab projection did not start")

        #expect(adapter.tabs.map(\.id) == [existingTab.id])
        #expect(adapter.activeTabId == existingTab.id)

        newTabGate.release()
        #expect(await completionRecorder.wait(for: .published(.init(value: 2))))
        #expect(
            await waitForOutput {
                self.adapter.tabs.map(\.id) == [existingTab.id, newTab.id]
                    && self.adapter.activeTabId == newTab.id
            },
            "Selected new tab did not publish with the complete aggregate"
        )
    }

    @Test("tab bar telemetry records capture worker terminal publication current and visible lifecycle")
    func telemetryRecordsCompleteMaterializationLifecycle() async throws {
        let traceDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-tabbar-telemetry-tests")
            .appending(path: UUIDv7.generate().uuidString)
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "tabbar-lifecycle",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 760,
            sessionID: "tabbar-lifecycle-session",
            timeUnixNano: { 7600 }
        )
        let performanceTraceRecorder = AgentStudioPerformanceTraceRecorder(traceRuntime: traceRuntime)
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let measuredProject: @Sendable (TabBarProjectionRequest) throws(CancellationError) -> TabBarProjection =
            { request in
                var projectionWorkChecksum: UInt64 = 0
                for workIndex in 0..<200_000 {
                    projectionWorkChecksum &+= UInt64(workIndex)
                }
                _ = projectionWorkChecksum
                return try TabBarProjector.project(request)
            }
        let pane = store.createPane(title: "Measured")
        let tab = Tab(paneId: pane.id, name: "Measured")
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            performanceTraceRecorder: performanceTraceRecorder,
            project: measuredProject,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await completionRecorder.wait(for: .published(.init(value: 1))))

        adapter.visibleProjectionDidRender()
        try await performanceTraceRecorder.drain()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.occurrenceCount(of: "\"body\":\"performance.tabbar.capture\"") == 1)
        #expect(contents.occurrenceCount(of: "\"body\":\"performance.tabbar.refresh\"") == 1)
        #expect(contents.occurrenceCount(of: "\"body\":\"performance.tabbar.worker\"") == 1)
        #expect(contents.occurrenceCount(of: "\"body\":\"performance.tabbar.terminal\"") == 1)
        #expect(contents.occurrenceCount(of: "\"body\":\"performance.tabbar.current\"") == 1)
        #expect(contents.occurrenceCount(of: "\"body\":\"performance.tabbar.publication\"") == 1)
        #expect(contents.occurrenceCount(of: "\"body\":\"performance.tabbar.visible\"") == 1)
        #expect(contents.contains("\"agentstudio.performance.tabbar.sequence\":1"))
        #expect(contents.contains("\"agentstudio.performance.tabbar.tab.count\":1"))
        #expect(contents.contains("\"agentstudio.performance.tabbar.pane.count\":1"))
        #expect(contents.contains("\"agentstudio.performance.tabbar.terminal.outcome\":\"published\""))
        #expect(contents.contains("\"agentstudio.performance.tabbar.active_tab.present\":true"))
        let refreshElapsedMilliseconds = try tabBarTelemetryElapsedMilliseconds(
            for: "performance.tabbar.refresh",
            in: contents
        )
        let workerElapsedMilliseconds = try tabBarTelemetryElapsedMilliseconds(
            for: "performance.tabbar.worker",
            in: contents
        )
        #expect(
            refreshElapsedMilliseconds < workerElapsedMilliseconds,
            "Tab Bar refresh must measure MainActor publication work, not include off-main projection"
        )
    }

    @Test("stop immediately settles an admitted projection exactly once")
    func stopImmediatelySettlesAdmissionWithoutLateDuplicate() async throws {
        let projectionGate = TabBarAdapterProjectionGate()
        defer { projectionGate.release() }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: projectionGate]
        )
        let traceDirectory = FileManager.default.temporaryDirectory
            .appending(path: "agentstudio-tabbar-stop-telemetry-tests")
            .appending(path: UUIDv7.generate().uuidString)
        let traceRuntime = AgentStudioTraceRuntime(
            configuration: AgentStudioTraceConfiguration.from(environment: [
                "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                "AGENTSTUDIO_TRACE_NAME": "tabbar-stop-lifecycle",
                "AGENTSTUDIO_TRACE_TAGS": "performance",
            ]),
            processIdentifier: 761,
            sessionID: "tabbar-stop-lifecycle-session",
            timeUnixNano: { 7610 }
        )
        let performanceTraceRecorder = AgentStudioPerformanceTraceRecorder(traceRuntime: traceRuntime)
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Stopping")
        store.appendTab(Tab(paneId: pane.id, name: "Stopping"))
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            performanceTraceRecorder: performanceTraceRecorder,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await projectionGate.waitUntilStarted(), "Held projection did not start")

        adapter.stop()
        try await performanceTraceRecorder.flush()

        let outputFileURL = try #require(traceRuntime.outputFileURL)
        var contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.occurrenceCount(of: "\"body\":\"performance.tabbar.terminal\"") == 1)
        #expect(contents.contains("\"agentstudio.performance.tabbar.terminal.outcome\":\"cancelled\""))

        projectionGate.release()
        #expect(await completionRecorder.wait(for: .cancelled(.init(value: 1))))
        try await performanceTraceRecorder.flush()
        contents = try String(contentsOf: outputFileURL, encoding: .utf8)
        #expect(contents.occurrenceCount(of: "\"body\":\"performance.tabbar.terminal\"") == 1)
    }

    @Test("stop permits adapter and materialized projection release")
    func stopBeforeProjectionReleaseReleasesAdapterAndMaterializedProjection() async {
        let projectionGate = TabBarAdapterProjectionGate()
        defer { projectionGate.release() }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: projectionGate]
        )
        let pane = store.createPane(title: "Stopping")
        let tab = Tab(paneId: pane.id, name: "Stopping")
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project
        )
        #expect(await projectionGate.waitUntilStarted(), "Held projection did not start")
        weak let weakAdapter = adapter
        weak let weakMaterializedProjection = adapter.materializedProjection(for: tab.id)

        adapter.stop()
        adapter = nil

        #expect(weakAdapter == nil)
        #expect(weakMaterializedProjection == nil)
    }

    @Test("stop cancels held projection and suppresses output")
    func stopBeforeProjectionReleaseSuppressesOutput() async {
        let projectionGate = TabBarAdapterProjectionGate()
        defer { projectionGate.release() }
        let projectionController = TabBarAdapterProjectionController(
            gatesByGeneration: [1: projectionGate]
        )
        let completionRecorder = TabBarAdapterProjectionCompletionRecorder()
        let pane = store.createPane(title: "Stopping")
        let tab = Tab(paneId: pane.id, name: "Stopping")
        store.appendTab(tab)
        adapter.stop()
        adapter = TabBarAdapter(
            store: store,
            repoCache: repoCache,
            inboxAtom: inboxAtom,
            project: projectionController.project,
            onProjectionCompletion: completionRecorder.record
        )
        #expect(await projectionGate.waitUntilStarted(), "Held projection did not start")
        let retainedMaterializedProjection = adapter.materializedProjection(for: tab.id)

        adapter.stop()
        projectionGate.release()
        #expect(await completionRecorder.wait(for: .cancelled(.init(value: 1))))

        #expect(retainedMaterializedProjection?.value == nil)
        #expect(retainedMaterializedProjection?.freshness == .stopped)
    }

    private func waitUntil(
        attempts: Int = 10_000,
        predicate: () -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            if predicate() { return true }
            await Task.yield()
        }
        return predicate()
    }

    private func waitForOutput(
        _ predicate: @escaping @MainActor () -> Bool
    ) async -> Bool {
        await TabBarAdapterConditionWaiter(condition: predicate).wait()
    }

}

extension String {
    fileprivate func occurrenceCount(of substring: String) -> Int {
        components(separatedBy: substring).count - 1
    }
}
