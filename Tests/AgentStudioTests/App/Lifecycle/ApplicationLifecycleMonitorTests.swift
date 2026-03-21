import Foundation
import Testing

@testable import AgentStudio

@Suite(.serialized)
@MainActor
struct ApplicationLifecycleMonitorTests {
    @Test("can be created with lifecycle stores and keeps only the two store dependencies")
    func test_applicationLifecycleMonitor_initializesWithStores() {
        let appStore = AppLifecycleStore()
        let windowStore = WindowLifecycleStore()

        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )

        let mirror = Mirror(reflecting: monitor)
        #expect(mirror.children.count == 2)
        #expect(
            mirror.children.compactMap(\.label).sorted() == [
                "appLifecycleStore",
                "windowLifecycleStore",
            ]
        )
    }

    @Test("marks termination synchronously when willTerminate ingress arrives")
    func test_applicationLifecycleMonitor_marksTerminationSynchronously() {
        let appStore = AppLifecycleStore()
        let windowStore = WindowLifecycleStore()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )

        monitor.handleApplicationWillTerminate()

        #expect(appStore.isTerminating == true)
    }
}
