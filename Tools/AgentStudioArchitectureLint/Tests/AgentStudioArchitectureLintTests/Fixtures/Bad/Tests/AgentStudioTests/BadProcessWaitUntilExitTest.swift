import Foundation

struct BadProcessWaitUntilExitTest {
    func waitsForProcessOnTheCooperativeThread() {
        let process = Process()
        process.waitUntilExit()
    }

    func waitsForProcessParameterOnTheCooperativeThread(process: Process) {
        process.waitUntilExit()
    }

    func waitsForQualifiedProcessParameterOnTheCooperativeThread(process: Foundation.Process) {
        process.waitUntilExit()
    }

    func waitsForTypedClosureProcessParameterOnTheCooperativeThread() {
        let waitForProcess: (Process) -> Void = { (process: Process) in
            process.waitUntilExit()
        }
        waitForProcess(Process())
    }
}
