import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore
@testable import AgentStudioInfrastructure
@testable import AgentStudioTestSupport

@MainActor
@Suite("Tab bar affected-item telemetry", .serialized)
struct TabBarAffectedItemTelemetryTests {
    @Test("one pane title mutation reports one affected tab bar item")
    func onePaneTitleMutationReportsOneAffectedTabBarItem() async throws {
        try await withAsyncTestCoreAtoms { _ in
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
            let store = WorkspaceStore()
            let adapter = TabBarAdapter(
                store: store,
                repoCache: RepoCacheAtom(),
                performanceTraceRecorder: recorder
            )
            let firstPane = store.createPane(title: "First")
            let secondPane = store.createPane(title: "Second")
            store.appendTab(Tab(paneId: firstPane.id))
            store.appendTab(Tab(paneId: secondPane.id))
            await eventually("initial tab items") {
                adapter.tabs.count == 2
            }
            try await recorder.drain()

            let outputFileURL = try #require(runtime.outputFileURL)
            let initialContents = try String(contentsOf: outputFileURL, encoding: .utf8)
            let initialEventCount =
                initialContents.components(
                    separatedBy: "\"body\":\"performance.tabbar.refresh\""
                ).count - 1

            store.paneAtom.updatePaneTitle(firstPane.id, title: "Renamed")
            await eventually("renamed tab item") {
                adapter.tabs.first(where: { $0.panes.contains { $0.id == firstPane.id } })?.title == "Renamed"
            }
            try await recorder.drain()

            let finalContents = try String(contentsOf: outputFileURL, encoding: .utf8)
            let finalEventCount =
                finalContents.components(
                    separatedBy: "\"body\":\"performance.tabbar.refresh\""
                ).count - 1
            #expect(finalEventCount == initialEventCount + 1)
            let finalLine = try #require(
                finalContents.split(separator: "\n").last { line in
                    line.contains("\"body\":\"performance.tabbar.refresh\"")
                }
            )
            #expect(finalLine.contains("\"agentstudio.performance.tabbar.affected_item.count\":1"))
            _ = adapter
        }
    }

}
