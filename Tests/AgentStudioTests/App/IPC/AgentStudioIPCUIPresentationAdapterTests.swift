import AgentStudioAppIPC
import AgentStudioProgrammaticControl
import Foundation
import Testing

@testable import AgentStudio

@MainActor
@Suite("AgentStudio IPC UI presentation adapter")
struct AgentStudioIPCUIPresentationAdapterTests {
    @Test("opens command bar through presenter-owned result for every scope")
    func opensCommandBarThroughPresenterOwnedResultForEveryScope() throws {
        let windowId = UUID()
        let presenter = RecordingIPCUIPresenter(resultWindowId: windowId)
        let adapter = AgentStudioIPCUIPresentationAdapter(
            presenter: presenter,
            targetAuthorizer: RecordingDurableTargetAuthorizer(paneIds: [])
        )
        let correlationId = UUID()

        for scope in [IPCCommandBarScope.everything, .commands, .panes, .repos] {
            let result = try adapter.openCommandBar(
                IPCCommandBarOpenParams(scope: scope, correlationId: correlationId)
            )

            #expect(
                result
                    == IPCCommandBarOpenResult(
                        workspaceWindowId: windowId,
                        scope: scope,
                        correlationId: correlationId
                    ))
        }
        #expect(presenter.presentedScopes == [.everything, .commands, .panes, .repos])
    }

    @Test("propagates no active window from presenter")
    func propagatesNoActiveWindowFromPresenter() throws {
        let presenter = RecordingIPCUIPresenter(error: AppIPCUIPresentationError(reason: .noActiveWindow))
        let adapter = AgentStudioIPCUIPresentationAdapter(
            presenter: presenter,
            targetAuthorizer: RecordingDurableTargetAuthorizer(paneIds: [])
        )

        do {
            _ = try adapter.openCommandBar(IPCCommandBarOpenParams(scope: .repos, correlationId: nil))
            Issue.record("command bar unexpectedly opened without an active window")
        } catch let error as AppIPCUIPresentationError {
            #expect(error.reason == .noActiveWindow)
        }

        do {
            _ = try adapter.openArrangements(
                IPCArrangementsOpenParams(targetPaneHandle: nil, correlationId: nil)
            )
            Issue.record("Arrangements unexpectedly opened without an active window")
        } catch let error as AppIPCUIPresentationError {
            #expect(error.reason == .noActiveWindow)
        }
    }

    @Test("opens Arrangements for an authorized durable pane and preserves correlation")
    func opensArrangementsForAuthorizedDurablePane() throws {
        let windowId = UUID()
        let tabId = UUID()
        let paneId = UUID()
        let correlationId = UUID()
        let presenter = RecordingIPCUIPresenter(
            resultWindowId: windowId,
            resultTabId: tabId
        )
        let adapter = AgentStudioIPCUIPresentationAdapter(
            presenter: presenter,
            targetAuthorizer: RecordingDurableTargetAuthorizer(paneIds: [paneId])
        )

        let result = try adapter.openArrangements(
            IPCArrangementsOpenParams(
                targetPaneHandle: "pane:\(paneId.uuidString)",
                correlationId: correlationId
            )
        )

        #expect(
            result
                == IPCArrangementsOpenResult(
                    workspaceWindowId: windowId,
                    tabId: tabId,
                    contextPaneId: paneId,
                    correlationId: correlationId
                )
        )
        #expect(presenter.presentedArrangementPaneIds == [paneId])
    }

    @Test("rejects stale companion and non-pane Arrangements targets before presentation")
    func rejectsInvalidArrangementsTargets() throws {
        let durablePaneId = UUID()
        let staleOrCompanionPaneId = UUID()
        let presenter = RecordingIPCUIPresenter()
        let adapter = AgentStudioIPCUIPresentationAdapter(
            presenter: presenter,
            targetAuthorizer: RecordingDurableTargetAuthorizer(paneIds: [durablePaneId])
        )

        for targetHandle in [
            "pane:\(staleOrCompanionPaneId.uuidString)",
            "tab:\(UUID().uuidString)",
            "pane:1",
            "not-a-handle",
        ] {
            #expect(throws: AppIPCUIPresentationError.self) {
                try adapter.openArrangements(
                    IPCArrangementsOpenParams(
                        targetPaneHandle: targetHandle,
                        correlationId: nil
                    )
                )
            }
        }
        #expect(presenter.presentedArrangementPaneIds.isEmpty)
    }
}

@MainActor
private final class RecordingIPCUIPresenter: AgentStudioIPCUIPresenting {
    private let resultWindowId: UUID
    private let resultTabId: UUID
    private let error: AppIPCUIPresentationError?
    private(set) var presentedScopes: [IPCCommandBarScope] = []
    private(set) var presentedArrangementPaneIds: [UUID?] = []

    init(
        resultWindowId: UUID = UUID(),
        resultTabId: UUID = UUID(),
        error: AppIPCUIPresentationError? = nil
    ) {
        self.resultWindowId = resultWindowId
        self.resultTabId = resultTabId
        self.error = error
    }

    func presentCommandBar(scope: IPCCommandBarScope) throws -> IPCCommandBarOpenResult {
        if let error {
            throw error
        }
        presentedScopes.append(scope)
        return IPCCommandBarOpenResult(workspaceWindowId: resultWindowId, scope: scope, correlationId: nil)
    }

    func presentArrangements(contextPaneId: UUID?) throws -> IPCArrangementsOpenResult {
        if let error {
            throw error
        }
        presentedArrangementPaneIds.append(contextPaneId)
        return IPCArrangementsOpenResult(
            workspaceWindowId: resultWindowId,
            tabId: resultTabId,
            contextPaneId: contextPaneId,
            correlationId: nil
        )
    }
}

@MainActor
private final class RecordingDurableTargetAuthorizer: WorkspaceDurableTargetAuthorizing {
    private let paneIds: Set<UUID>

    init(paneIds: Set<UUID>) {
        self.paneIds = paneIds
    }

    func containsRepository(id _: UUID) -> Bool {
        false
    }

    func containsTab(id _: UUID) -> Bool {
        false
    }

    func containsPane(id: UUID) -> Bool {
        paneIds.contains(id)
    }
}
