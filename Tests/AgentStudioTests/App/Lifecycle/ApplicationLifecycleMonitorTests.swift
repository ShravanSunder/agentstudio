import Foundation
import Testing

@testable import AgentStudio
@testable import AgentStudioCore

@Suite(.serialized)
@MainActor
struct ApplicationLifecycleMonitorTests {
    @Test("can be created with lifecycle stores")
    func test_applicationLifecycleMonitor_initializesWithStores() {
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()

        _ = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
    }

    @Test("routes application active and inactive facts")
    func routesApplicationActivityFacts() {
        // Arrange
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )

        // Act and assert: active
        monitor.handleApplicationDidBecomeActive()
        #expect(appStore.isActive)

        // Act and assert: inactive
        monitor.handleApplicationDidResignActive()
        #expect(!appStore.isActive)
    }

    @Test("marks termination synchronously when willTerminate ingress arrives")
    func test_applicationLifecycleMonitor_marksTerminationSynchronously() {
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )

        monitor.handleApplicationWillTerminate()

        #expect(appStore.isTerminating == true)
    }

    @Test("updates window lifecycle store through key-window ingress")
    func test_applicationLifecycleMonitor_updatesWindowLifecycleStore() {
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
        let windowId = UUID()

        monitor.handleWindowRegistered(windowId)
        monitor.handleWindowDidBecomeKey(windowId)
        monitor.handleWindowDidResignKey(windowId)

        #expect(windowStore.registeredWindowIds.contains(windowId))
        #expect(windowStore.keyWindowId == nil)
        #expect(windowStore.focusedWindowId == nil)
    }

    @Test("writes complete AppKit window presentation facts")
    func writesCompleteWindowPresentationFacts() throws {
        // Arrange
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
        let windowId = UUID()
        monitor.handleWindowRegistered(windowId)

        // Act
        monitor.handleWindowPresentationChanged(
            windowId,
            isVisible: true,
            isMiniaturized: false,
            isOccluded: false
        )

        // Assert
        #expect(
            try #require(windowStore.presentationFacts(for: windowId))
                == WindowPresentationFacts(isVisible: true, isMiniaturized: false, isOccluded: false)
        )
    }

    @Test("writes terminal container bounds to the window lifecycle store")
    func test_applicationLifecycleMonitor_writesTerminalContainerBounds() {
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
        let bounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

        monitor.handleTerminalContainerBoundsChanged(bounds)

        #expect(windowStore.terminalContainerBounds == bounds)
        #expect(windowStore.isReadyForLaunchRestore == false)
    }

    @Test("ignores empty terminal container bounds")
    func test_applicationLifecycleMonitor_ignoresEmptyTerminalContainerBounds() {
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
        let initialBounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

        monitor.handleTerminalContainerBoundsChanged(initialBounds)
        monitor.handleTerminalContainerBoundsChanged(.zero)

        #expect(windowStore.terminalContainerBounds == initialBounds)
    }

    @Test("marks launch layout as settled in the window lifecycle store")
    func test_applicationLifecycleMonitor_marksLaunchLayoutSettled() {
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )

        monitor.handleLaunchLayoutSettled()

        #expect(windowStore.isLaunchLayoutSettled == true)
        #expect(windowStore.isReadyForLaunchRestore == false)
    }

    @Test("marking launch layout settled preserves previously recorded bounds")
    func test_applicationLifecycleMonitor_settledPreservesExistingBounds() {
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )
        let bounds = CGRect(x: 0, y: 0, width: 1140, height: 824)

        monitor.handleTerminalContainerBoundsChanged(bounds)
        monitor.handleLaunchLayoutSettled()

        #expect(windowStore.terminalContainerBounds == bounds)
        #expect(windowStore.isLaunchLayoutSettled == true)
        #expect(windowStore.isReadyForLaunchRestore == true)
    }

    @Test("display completion is scheduled only after launch layout readiness")
    func schedulesDisplayCompletionAtReadinessEdge() {
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()
        var scheduledCompletion: (@MainActor () -> Void)?
        var scheduleCount = 0
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore,
            scheduleFirstDisplayCommit: { completion in
                scheduleCount += 1
                scheduledCompletion = completion
            }
        )

        monitor.handleLaunchLayoutSettled()
        #expect(scheduleCount == 0)
        monitor.handleTerminalContainerBoundsChanged(CGRect(x: 0, y: 0, width: 1140, height: 824))
        #expect(scheduleCount == 1)
        #expect(!windowStore.didPublishFirstInteractiveFrame)

        scheduledCompletion?()
        #expect(windowStore.didPublishFirstInteractiveFrame)

        monitor.handleLaunchLayoutSettled()
        #expect(scheduleCount == 1)
    }

    @Test("completion before launch readiness cannot publish the proxy frame")
    func ignoresPreReadyDisplayCompletion() {
        let appStore = AppLifecycleAtom()
        let windowStore = WindowLifecycleAtom()
        let monitor = ApplicationLifecycleMonitor(
            appLifecycleStore: appStore,
            windowLifecycleStore: windowStore
        )

        monitor.handleFirstDisplayCommitCompleted()

        #expect(!windowStore.didPublishFirstInteractiveFrame)
    }

}
