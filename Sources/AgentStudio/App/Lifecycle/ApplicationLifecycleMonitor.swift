import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

@MainActor
final class ApplicationLifecycleMonitor {
    typealias ScheduleFirstDisplayCommit = (@escaping @MainActor () -> Void) -> Void

    private let appLifecycleStore: AppLifecycleAtom
    private let windowLifecycleStore: WindowLifecycleAtom
    private let performanceTraceRecorder: AgentStudioPerformanceTraceRecorder?
    private let now: @MainActor () -> ContinuousClock.Instant
    private var scheduleFirstDisplayCommit: ScheduleFirstDisplayCommit
    private var didScheduleFirstDisplayCommit = false
    private var launchLayoutSettledInstant: ContinuousClock.Instant?

    init(
        appLifecycleStore: AppLifecycleAtom,
        windowLifecycleStore: WindowLifecycleAtom,
        performanceTraceRecorder: AgentStudioPerformanceTraceRecorder? = nil,
        now: @escaping @MainActor () -> ContinuousClock.Instant = { ContinuousClock.now },
        scheduleFirstDisplayCommit: @escaping ScheduleFirstDisplayCommit = { _ in }
    ) {
        self.appLifecycleStore = appLifecycleStore
        self.windowLifecycleStore = windowLifecycleStore
        self.performanceTraceRecorder = performanceTraceRecorder
        self.now = now
        self.scheduleFirstDisplayCommit = scheduleFirstDisplayCommit
    }

    func installFirstDisplayCommitScheduler(_ scheduler: @escaping ScheduleFirstDisplayCommit) {
        scheduleFirstDisplayCommit = scheduler
        scheduleFirstDisplayCommitIfReady()
    }

    func handleApplicationDidBecomeActive() {
        appLifecycleStore.setActive(true)
    }

    func handleApplicationDidResignActive() {
        appLifecycleStore.setActive(false)
    }

    func handleApplicationWillTerminate(onWillTerminate: () -> Void = {}) {
        appLifecycleStore.markTerminating()
        onWillTerminate()
    }

    func handleWindowRegistered(_ windowId: UUID) {
        windowLifecycleStore.recordWindowRegistered(windowId)
    }

    func handleWindowPresentationChanged(
        _ windowId: UUID,
        isVisible: Bool,
        isMiniaturized: Bool,
        isOccluded: Bool
    ) {
        windowLifecycleStore.recordWindowPresentation(
            WindowPresentationFacts(
                isVisible: isVisible,
                isMiniaturized: isMiniaturized,
                isOccluded: isOccluded
            ),
            for: windowId
        )
    }

    func handleWindowDidBecomeKey(_ windowId: UUID) {
        windowLifecycleStore.recordWindowBecameKey(windowId)
        windowLifecycleStore.recordWindowBecameFocused(windowId)
    }

    func handleWindowDidResignKey(_ windowId: UUID) {
        windowLifecycleStore.recordWindowResignedKey(windowId)
        windowLifecycleStore.recordWindowResignedFocused(windowId)
    }

    func handleTerminalContainerBoundsChanged(_ bounds: CGRect) {
        guard !bounds.isEmpty else { return }
        RestoreTrace.log(
            "ApplicationLifecycleMonitor.handleTerminalContainerBoundsChanged bounds=\(NSStringFromRect(bounds))"
        )
        windowLifecycleStore.recordTerminalContainerBounds(bounds)
        scheduleFirstDisplayCommitIfReady()
    }

    func handleLaunchLayoutSettled() {
        RestoreTrace.log(
            "ApplicationLifecycleMonitor.handleLaunchLayoutSettled bounds=\(NSStringFromRect(windowLifecycleStore.terminalContainerBounds)) settled(before)=\(windowLifecycleStore.isLaunchLayoutSettled)"
        )
        if !windowLifecycleStore.isLaunchLayoutSettled {
            launchLayoutSettledInstant = now()
            windowLifecycleStore.recordLaunchLayoutSettled()
        }
        scheduleFirstDisplayCommitIfReady()
    }

    func handleFirstDisplayCommitCompleted() {
        guard windowLifecycleStore.isReadyForLaunchRestore else { return }
        guard windowLifecycleStore.recordFirstInteractiveFramePublished() else { return }
        guard let performanceTraceRecorder,
            let launchLayoutSettledInstant
        else { return }
        let usableInstant = now()
        performanceTraceRecorder.recordStartupUsable(
            launchToUsable: performanceTraceRecorder.startupLaunchInstant.duration(to: usableInstant),
            layoutSettleToUsable: launchLayoutSettledInstant.duration(to: usableInstant)
        )
    }

    private func scheduleFirstDisplayCommitIfReady() {
        guard windowLifecycleStore.isReadyForLaunchRestore,
            !didScheduleFirstDisplayCommit,
            !windowLifecycleStore.didPublishFirstInteractiveFrame
        else { return }
        didScheduleFirstDisplayCommit = true
        scheduleFirstDisplayCommit { [weak self] in
            self?.handleFirstDisplayCommitCompleted()
        }
    }
}
