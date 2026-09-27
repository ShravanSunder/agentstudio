import Dispatch
import Foundation

func runsScriptUnderExplicitTimeout() async throws {
    _ = try await DefaultProcessExecutor(timeout: 10).execute(command: "bash", args: [], cwd: nil, environment: nil)
}

func runsScriptUnderDefaultTimeout() async throws {
    _ = try await DefaultProcessExecutor().execute(command: "bash", args: [], cwd: nil, environment: nil)
}

func runsScriptUnderQualifiedExecutor() async throws {
    _ = try await AgentStudioInfrastructure.DefaultProcessExecutor(timeout: 5).execute(
        command: "bash", args: [], cwd: nil, environment: nil)
}

func waitsForLocalSemaphoreWithDeadline() async {
    let completion = DispatchSemaphore(value: 0)
    _ = await withoutBlockingCooperativePool { completion.wait(timeout: .now() + 20) }
}

func waitsForGroupParameterWithWallDeadline(group: DispatchGroup) async {
    _ = await withoutBlockingCooperativePool { group.wait(wallTimeout: .now() + 5) }
}

final class BudgetedRelease: @unchecked Sendable {
    private let releaseSignal = DispatchSemaphore(value: 0)

    func hold() -> Bool {
        self.releaseSignal.wait(timeout: .now() + .seconds(5)) == .success
    }

    func expireLater(_ expire: @escaping @Sendable () -> Void) {
        DispatchQueue.global().asyncAfter(deadline: .now() + .seconds(5), execute: expire)
    }
}

func waitsForFileWithBudget(fixture: LauncherFixture, url: URL) throws {
    try fixture.waitForFile(url, containing: "ready", timeoutSeconds: 5)
}

func runsScriptUnderExplicitInitTimeout() async throws {
    _ = try await DefaultProcessExecutor.init(timeout: 10).execute(
        command: "bash", args: [], cwd: nil, environment: nil)
}

func waitsForSemaphoreInitWithDeadline() async {
    _ = await DispatchSemaphore.init(value: 0).wait(timeout: .now() + 20)
}

func waitsForGroupInitWithWallDeadline() async {
    _ = await DispatchGroup.init().wait(wallTimeout: .now() + 5)
}
