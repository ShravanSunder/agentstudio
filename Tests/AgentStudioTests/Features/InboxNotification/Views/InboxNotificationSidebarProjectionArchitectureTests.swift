import Foundation
import Testing

@Suite("InboxNotificationSidebarView projection architecture")
struct InboxSidebarProjectionArchitectureTests {
    @Test("sidebar view routes list projection through worker with generation guards")
    func sidebarViewRoutesProjectionThroughWorkerWithGenerationGuards() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift"),
            encoding: .utf8
        )

        #expect(source.contains("InboxNotificationListProjectionWorker()"))
        #expect(source.contains("try await worker.project(request)"))
        #expect(source.contains("refreshListModel(force: true)"))
        #expect(source.contains("State(initialValue: .empty)"))
        #expect(source.contains("result.generation == projectionGeneration"))
        #expect(source.contains("result.key == inFlightProjectionRequest?.key"))
        #expect(source.contains("cachedListModelKey = result.key"))
        #expect(source.contains("agentstudio.performance.sidebar.stale_discard.count"))
        #expect(source.contains("agentstudio.performance.sidebar.cancellation.count"))
        #expect(!source.contains("State(\n            initialValue: InboxNotificationListModel("))
        #expect(!source.contains("performanceTraceRecorder?.measure(\n                .sidebarProjection"))
    }

    @Test("projection worker uses cancellable detached work")
    func projectionWorkerUsesCancellableDetachedWork() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path:
                    "Sources/AgentStudio/Features/InboxNotification/Models/InboxNotificationListProjectionWorker.swift"),
            encoding: .utf8
        )

        #expect(source.contains("Task." + "detached(priority: .userInitiated)"))
        #expect(source.contains("withTaskCancellationHandler"))
        #expect(source.contains("projectionTask.cancel()"))
        #expect(source.contains("try Task.checkCancellation()"))
    }

    @Test("temporary display override is read before it is cleared")
    func temporaryDisplayOverrideIsReadBeforeItIsCleared() throws {
        let projectRoot = URL(fileURLWithPath: TestPathResolver.projectRoot(from: #filePath))
        let source = try String(
            contentsOf: projectRoot.appending(
                path: "Sources/AgentStudio/Features/InboxNotification/Views/InboxNotificationSidebarView.swift"),
            encoding: .utf8
        )

        let rowFilterRead = try #require(source.range(of: "let nextRowStateFilter"))
        let contentModeRead = try #require(source.range(of: "let nextContentMode"))
        let rowFilterClear = source.range(
            of: "displayOverride = nil",
            range: rowFilterRead.upperBound..<contentModeRead.lowerBound
        )
        let contentModeClear = source.range(
            of: "displayOverride = nil",
            range: contentModeRead.upperBound..<source.endIndex
        )

        #expect(rowFilterClear != nil)
        #expect(contentModeClear != nil)
    }
}
