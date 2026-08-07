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

}
