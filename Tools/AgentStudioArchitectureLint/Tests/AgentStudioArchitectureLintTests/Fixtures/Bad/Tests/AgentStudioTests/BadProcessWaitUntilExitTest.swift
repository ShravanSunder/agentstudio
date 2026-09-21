import Foundation

struct BadProcessWaitUntilExitTest {
    func waitsForProcessOnTheCooperativeThread() {
        let process = Process()
        process.waitUntilExit()
    }
}
