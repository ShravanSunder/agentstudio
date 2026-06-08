import AppKit
import Testing

@testable import AgentStudio

@MainActor
@Suite("AppDelegate lifecycle routing")
struct AppDelegateLifecycleRoutingTests {
    @Test("activation ingress before workspace boot does not require lifecycle stores")
    func activationIngressBeforeWorkspaceBootDoesNotRequireLifecycleStores() {
        let delegate = AppDelegate()

        delegate.applicationDidBecomeActive(
            Notification(name: NSApplication.didBecomeActiveNotification)
        )
        delegate.applicationDidResignActive(
            Notification(name: NSApplication.didResignActiveNotification)
        )
        delegate.applicationWillTerminate(
            Notification(name: NSApplication.willTerminateNotification)
        )
    }

    @Test("post-boot synchronization seeds active application state")
    func postBootSynchronizationSeedsActiveApplicationState() {
        let delegate = AppDelegate()
        let appLifecycleStore = AppLifecycleAtom()
        let windowLifecycleStore = WindowLifecycleAtom()
        delegate.appLifecycleStore = appLifecycleStore
        delegate.windowLifecycleStore = windowLifecycleStore
        delegate.applicationLifecycleMonitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appLifecycleStore,
            windowLifecycleStore: windowLifecycleStore
        )

        delegate.synchronizeApplicationLifecycleStateAfterWorkspaceBoot(isApplicationActive: true)

        #expect(appLifecycleStore.isActive)
    }
}
