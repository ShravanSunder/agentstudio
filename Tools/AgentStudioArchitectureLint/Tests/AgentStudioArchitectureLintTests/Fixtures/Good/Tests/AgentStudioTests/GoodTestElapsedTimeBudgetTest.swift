import Dispatch
import Foundation

struct GoodTestElapsedTimeBudgetTest {
    private let budgetMention = "DefaultProcessExecutor(timeout: 10) and semaphore.wait(timeout: .now() + 5)"

    func commentAndStringMentionsAreAllowed() {
        // DefaultProcessExecutor(timeout: 10) is policy text here, not a call.
        _ = budgetMention
    }

    func runsScriptToExit() async throws {
        _ = try await RunToExitProcessExecutor().execute(command: "bash", args: [], cwd: nil, environment: nil)
    }

    func waitsForSemaphoreUntimedOffThePool(semaphore: DispatchSemaphore) async {
        await withoutBlockingCooperativePool { semaphore.wait() }
    }

    func readsTheFileEvent(fixture: LauncherFixture, url: URL) async throws {
        try await fixture.waitForFile(url, containing: "ready")
    }

    func passesTheProductTimeoutToTheOwnerUnderTest(runtime: FakeRuntime) async {
        await runtime.shutdown(timeout: .seconds(1))
    }

    func leavesAnUnrelatedTimedWaitAlone(mailbox: FakeMailbox) -> Bool {
        mailbox.wait(timeout: 1)
    }
}

struct FakeRuntime {
    func shutdown(timeout: Duration) async {}
}

struct FakeMailbox {
    func wait(timeout: Int) -> Bool { timeout > 0 }
}
