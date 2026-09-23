import Foundation

struct GoodProcessWaitUntilExitTest {
    func waitsForProcessOffTheCooperativePool() async throws {
        let process = Process()
        try await withoutBlockingCooperativePool {
            process.waitUntilExit()
        }
    }

    func allowsAnUnrelatedMethodWithTheSameName(lifecycle: FakeProcessLifecycle) {
        lifecycle.waitUntilExit()
    }

    func allowsAnUnrelatedReceiverWithTheConventionalName(process: FakeProcessLifecycle) {
        process.waitUntilExit()
    }

    func allowsALocalShadowWithTheConventionalName() {
        let process = FakeProcessLifecycle()
        process.waitUntilExit()
    }

    func allowsAClosureLocalProcessBindingToEnd(process: FakeProcessLifecycle) {
        let launchProcess = {
            let process = Process()
            _ = process
        }
        launchProcess()
        process.waitUntilExit()
    }

    func allowsATypedClosureParameterToShadowAnOuterProcess() {
        let process = Process()
        let waitForLifecycle: (FakeProcessLifecycle) -> Void = { (process: FakeProcessLifecycle) in
            process.waitUntilExit()
        }
        waitForLifecycle(FakeProcessLifecycle())
        _ = process
    }

    func allowsAShorthandClosureParameterToShadowAnOuterProcess() {
        let process = Process()
        let waitForLifecycle: (FakeProcessLifecycle) -> Void = { process in
            process.waitUntilExit()
        }
        waitForLifecycle(FakeProcessLifecycle())
        _ = process
    }
}

struct FakeProcessLifecycle {
    func waitUntilExit() {}
}
