import Foundation
import GhosttyKit
import Testing

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct GhosttyAppFocusSynchronizerTests {
    private final class RecordingFocusSetter: GhosttyAppFocusSetting {
        let focusChanges: AsyncStream<Bool>
        private let continuation: AsyncStream<Bool>.Continuation
        private(set) var deliveredValues: [Bool] = []

        init() {
            (focusChanges, continuation) = AsyncStream.makeStream(of: Bool.self)
        }

        deinit {
            continuation.finish()
        }

        func setAppFocus(_ app: ghostty_app_t, isActive: Bool) {
            deliveredValues.append(isActive)
            continuation.yield(isActive)
        }
    }

    @Test("pushes lifecycle focus changes to Ghostty")
    func focusSynchronizer_pushesLifecycleFocusChangesToGhostty() async {
        let appLifecycleStore = AppLifecycleStore()
        let focusSetter = RecordingFocusSetter()
        let synchronizer = Ghostty.AppFocusSynchronizer(focusSetter: focusSetter)
        var focusIterator = focusSetter.focusChanges.makeAsyncIterator()

        synchronizer.updateAppHandle(UnsafeMutableRawPointer(bitPattern: 1))
        synchronizer.bindApplicationLifecycleStore(appLifecycleStore)

        let initialValue = await focusIterator.next()
        #expect(initialValue == false)

        appLifecycleStore.setActive(true)
        let activeValue = await focusIterator.next()
        #expect(activeValue == true)

        appLifecycleStore.setActive(false)
        let inactiveValue = await focusIterator.next()
        #expect(inactiveValue == false)
    }

    @Test("rejects rebinding to a different lifecycle store")
    func focusSynchronizer_rejectsRebindingToDifferentStore() async {
        let initialStore = AppLifecycleStore()
        let secondStore = AppLifecycleStore()
        let focusSetter = RecordingFocusSetter()
        let synchronizer = Ghostty.AppFocusSynchronizer(focusSetter: focusSetter)
        var focusIterator = focusSetter.focusChanges.makeAsyncIterator()

        synchronizer.updateAppHandle(UnsafeMutableRawPointer(bitPattern: 1))
        synchronizer.bindApplicationLifecycleStore(initialStore)
        _ = await focusIterator.next()

        synchronizer.bindApplicationLifecycleStore(secondStore)
        secondStore.setActive(true)

        #expect(focusSetter.deliveredValues == [false])

        initialStore.setActive(true)
        let reboundValue = await focusIterator.next()
        #expect(reboundValue == true)
    }
}
