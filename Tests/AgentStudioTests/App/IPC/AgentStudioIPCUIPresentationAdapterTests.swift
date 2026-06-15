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
        let adapter = AgentStudioIPCUIPresentationAdapter(presenter: presenter)
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
        let adapter = AgentStudioIPCUIPresentationAdapter(presenter: presenter)

        do {
            _ = try adapter.openCommandBar(IPCCommandBarOpenParams(scope: .repos, correlationId: nil))
            Issue.record("command bar unexpectedly opened without an active window")
        } catch let error as AppIPCUIPresentationError {
            #expect(error.reason == .noActiveWindow)
        }
    }
}

@MainActor
private final class RecordingIPCUIPresenter: AgentStudioIPCUIPresenting {
    private let resultWindowId: UUID
    private let error: AppIPCUIPresentationError?
    private(set) var presentedScopes: [IPCCommandBarScope] = []

    init(resultWindowId: UUID = UUID(), error: AppIPCUIPresentationError? = nil) {
        self.resultWindowId = resultWindowId
        self.error = error
    }

    func presentCommandBar(scope: IPCCommandBarScope) throws -> IPCCommandBarOpenResult {
        if let error {
            throw error
        }
        presentedScopes.append(scope)
        return IPCCommandBarOpenResult(workspaceWindowId: resultWindowId, scope: scope, correlationId: nil)
    }
}
