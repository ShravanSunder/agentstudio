import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInboxNotification
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Tab bar affected-item telemetry", .serialized)
struct TabBarAffectedItemTelemetryTests {
    @Test("one pane title mutation reports one affected tab bar item")
    func onePaneTitleMutationReportsOneAffectedTabBarItem() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let traceDirectory = FileManager.default.temporaryDirectory.appending(
                path: "tabbar-affected-item-trace-\(UUIDv7.generate().uuidString)"
            )
            defer { try? FileManager.default.removeItem(at: traceDirectory) }
            let runtime = AgentStudioTraceRuntime(
                configuration: AgentStudioTraceConfiguration.from(environment: [
                    "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                    "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                    "AGENTSTUDIO_TRACE_NAME": "tabbar-affected-item",
                    "AGENTSTUDIO_TRACE_TAGS": "performance",
                ]),
                processIdentifier: 932,
                timeUnixNano: { 932 }
            )
            let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let adapter = TabBarAdapter(
                store: store,
                repoCache: RepoCacheAtom(),
                inboxAtom: InboxNotificationAtom(),
                performanceTraceRecorder: recorder
            )
            let firstPane = store.createPane(title: "First")
            let secondPane = store.createPane(title: "Second")
            let firstTab = Tab(paneId: firstPane.id)
            store.appendTab(firstTab)
            store.appendTab(Tab(paneId: secondPane.id))
            await eventually("initial tab items") {
                adapter.tabs.count == 2
            }

            store.paneAtom.updatePaneTitle(firstPane.id, title: "Renamed")
            await eventually("renamed tab item") {
                adapter.tabs.first(where: { $0.id == firstTab.id })?.title == "Renamed"
            }
            try await recorder.drain()

            let outputFileURL = try #require(runtime.outputFileURL)
            let finalContents = try String(contentsOf: outputFileURL, encoding: .utf8)
            let refreshLines = finalContents.split(separator: "\n").filter { line in
                line.contains("\"body\":\"performance.tabbar.refresh\"")
            }
            #expect(refreshLines.count == 2)
            let finalLine = try #require(refreshLines.last)
            #expect(finalLine.contains("\"agentstudio.performance.tabbar.affected_item.count\":1"))
            _ = adapter
        }
    }

    @Test("active selection reorder and removal emit correlated publication telemetry")
    func collectionChangesEmitCorrelatedPublicationTelemetry() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let traceDirectory = FileManager.default.temporaryDirectory.appending(
                path: "tabbar-collection-trace-\(UUIDv7.generate().uuidString)"
            )
            defer { try? FileManager.default.removeItem(at: traceDirectory) }
            let runtime = AgentStudioTraceRuntime(
                configuration: AgentStudioTraceConfiguration.from(environment: [
                    "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                    "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                    "AGENTSTUDIO_TRACE_NAME": "tabbar-collection",
                    "AGENTSTUDIO_TRACE_TAGS": "performance",
                ]),
                processIdentifier: 933,
                timeUnixNano: { 933 }
            )
            let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
            let adapter = TabBarAdapter(
                store: store,
                repoCache: RepoCacheAtom(),
                inboxAtom: InboxNotificationAtom(),
                performanceTraceRecorder: recorder
            )
            let firstPane = store.createPane(title: "First")
            let secondPane = store.createPane(title: "Second")
            let firstTab = Tab(paneId: firstPane.id)
            let secondTab = Tab(paneId: secondPane.id)
            store.appendTab(firstTab)
            store.appendTab(secondTab)
            await eventually("initial tab items") {
                adapter.tabs.map(\.id) == [firstTab.id, secondTab.id]
                    && adapter.activeTabId == secondTab.id
            }
            adapter.visibleProjectionDidRender()

            let initialRevision = adapter.outputPublicationRevision
            store.setActiveTab(firstTab.id)
            await eventually("active tab publication") {
                adapter.activeTabId == firstTab.id
                    && adapter.outputPublicationRevision == initialRevision + 1
            }
            adapter.visibleProjectionDidRender()

            store.tabLayoutAtom.reorderTab(secondTab.id, to: 0)
            await eventually("tab reorder publication") {
                adapter.tabs.map(\.id) == [secondTab.id, firstTab.id]
                    && adapter.outputPublicationRevision == initialRevision + 2
            }
            adapter.visibleProjectionDidRender()

            store.removeTab(secondTab.id)
            await eventually("tab removal publication") {
                adapter.tabs.map(\.id) == [firstTab.id]
                    && adapter.outputPublicationRevision == initialRevision + 3
            }
            adapter.visibleProjectionDidRender()
            try await recorder.drain()

            let outputFileURL = try #require(runtime.outputFileURL)
            let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
            let eventBodies = [
                "performance.tabbar.refresh",
                "performance.tabbar.current",
                "performance.tabbar.publication",
                "performance.tabbar.visible",
            ]
            for eventBody in eventBodies {
                #expect(
                    tabBarTelemetryEventCount(for: eventBody, in: contents) == 4,
                    "Expected initial, active-selection, reorder, and removal publications for \(eventBody)"
                )
            }
            let refreshSequences = try tabBarTelemetrySequences(
                for: "performance.tabbar.refresh",
                in: contents
            )
            for eventBody in eventBodies.dropFirst() {
                #expect(try tabBarTelemetrySequences(for: eventBody, in: contents) == refreshSequences)
            }
            _ = adapter
        }
    }

    @Test("equal completion barrier emits correlated publication telemetry")
    func equalCompletionBarrierEmitsCorrelatedPublicationTelemetry() async throws {
        try await withAsyncTestCoreAtoms { atoms in
            let traceDirectory = FileManager.default.temporaryDirectory.appending(
                path: "tabbar-equal-barrier-trace-\(UUIDv7.generate().uuidString)"
            )
            defer { try? FileManager.default.removeItem(at: traceDirectory) }
            let runtime = AgentStudioTraceRuntime(
                configuration: AgentStudioTraceConfiguration.from(environment: [
                    "AGENTSTUDIO_TRACE_BACKEND": "jsonl",
                    "AGENTSTUDIO_TRACE_DIR": traceDirectory.path,
                    "AGENTSTUDIO_TRACE_NAME": "tabbar-equal-barrier",
                    "AGENTSTUDIO_TRACE_TAGS": "performance",
                ]),
                processIdentifier: 934,
                timeUnixNano: { 934 }
            )
            let recorder = AgentStudioPerformanceTraceRecorder(traceRuntime: runtime)
            let store = WorkspaceStore(
                catalogAtom: atoms.workspaceRepositoryTopology,
                graphAtom: atoms.workspacePane,
                interactionAtom: atoms.workspaceTabLayout
            )
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
            let adapter = TabBarAdapter(
                store: store,
                repoCache: RepoCacheAtom(),
                inboxAtom: InboxNotificationAtom(),
                performanceTraceRecorder: recorder,
                project: projectionController.project,
                onProjectionCompletion: completionRecorder.record
            )
            await eventually("initial coherent projection") {
                adapter.tabs.map(\.displayTitle) == ["First before", "Second before"]
            }
            adapter.visibleProjectionDidRender()

            store.renameTab(firstTab.id, name: "First source changed")
            store.renameTab(secondTab.id, name: "Second after")
            #expect(await equalRefreshGate.waitUntilStarted(), "Equal refresh did not start")
            #expect(await changedRefreshGate.waitUntilStarted(), "Changed refresh did not start")
            changedRefreshGate.release()
            #expect(await completionRecorder.wait(for: .published(.init(value: 4))))
            #expect(adapter.tabs.map(\.displayTitle) == ["First before", "Second before"])

            equalRefreshGate.release()
            #expect(await completionRecorder.wait(for: .equal(.init(value: 3))))
            await eventually("equal barrier publication") {
                adapter.tabs.map(\.displayTitle) == ["First before", "Second after"]
            }
            adapter.visibleProjectionDidRender()
            try await recorder.drain()

            let outputFileURL = try #require(runtime.outputFileURL)
            let contents = try String(contentsOf: outputFileURL, encoding: .utf8)
            let eventBodies = [
                "performance.tabbar.refresh",
                "performance.tabbar.current",
                "performance.tabbar.publication",
                "performance.tabbar.visible",
            ]
            let refreshSequences = try tabBarTelemetrySequences(
                for: "performance.tabbar.refresh",
                in: contents
            )
            #expect(refreshSequences.count == 2)
            for eventBody in eventBodies.dropFirst() {
                #expect(try tabBarTelemetrySequences(for: eventBody, in: contents) == refreshSequences)
            }
            _ = adapter
        }
    }

}

extension String {
    fileprivate func occurrenceCount(of substring: String) -> Int {
        components(separatedBy: substring).count - 1
    }
}

private func tabBarTelemetrySequences(
    for eventBody: String,
    in contents: String
) throws -> [Int] {
    try contents.split(separator: "\n").compactMap { line in
        guard line.contains("\"body\":\"\(eventBody)\"") else { return nil }
        let marker = "\"agentstudio.performance.tabbar.sequence\":"
        guard let markerRange = line.range(of: marker) else {
            throw TabBarTelemetryTestError.missingSequence(eventBody)
        }
        let suffix = line[markerRange.upperBound...]
        let digits = suffix.prefix { $0.isNumber }
        guard let sequence = Int(digits) else {
            throw TabBarTelemetryTestError.invalidSequence(eventBody)
        }
        return sequence
    }
}

private func tabBarTelemetryEventCount(for eventBody: String, in contents: String) -> Int {
    contents.split(separator: "\n").count { line in
        line.contains("\"body\":\"\(eventBody)\"")
    }
}

private enum TabBarTelemetryTestError: Error {
    case missingSequence(String)
    case invalidSequence(String)
}
