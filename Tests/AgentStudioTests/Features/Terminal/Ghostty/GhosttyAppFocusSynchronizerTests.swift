import Foundation
import GhosttyKit
import Testing
import os

@testable import AgentStudio

@MainActor
@Suite(.serialized)
struct GhosttyAppFocusSynchronizerTests {
    private final class RecordingFocusSetter: GhosttyAppFocusSetting {
        let focusChanges: AsyncStream<Bool>
        private let continuation: AsyncStream<Bool>.Continuation
        private let deliveredValuesLock = OSAllocatedUnfairLock<[Bool]>(initialState: [])

        var deliveredValues: [Bool] {
            deliveredValuesLock.withLock { $0 }
        }

        init() {
            (focusChanges, continuation) = AsyncStream.makeStream(of: Bool.self)
        }

        deinit {
            continuation.finish()
        }

        func setAppFocus(_ app: ghostty_app_t, isActive: Bool) {
            deliveredValuesLock.withLock {
                $0.append(isActive)
            }
            continuation.yield(isActive)
        }
    }

    private final class ClearCompletionProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var hasCompletedClear = false

        func markClearCompleted() {
            lock.withLock {
                hasCompletedClear = true
            }
        }

        var clearCompleted: Bool {
            lock.withLock {
                hasCompletedClear
            }
        }
    }

    @Test("handle bits keep clearing from interleaving with current handle use")
    func appHandleBits_blocksClearUntilCurrentHandleUseCompletes() {
        let handleBits = GhosttyAppHandleBits()
        let app = UnsafeMutableRawPointer(bitPattern: 0x1)!
        let appBits = UInt(bitPattern: app)
        let clearStarted = DispatchSemaphore(value: 0)
        let clearCompleted = DispatchSemaphore(value: 0)
        let clearProbe = ClearCompletionProbe()

        handleBits.update(app)

        handleBits.withCurrent { currentApp in
            #expect(UInt(bitPattern: currentApp) == appBits)

            DispatchQueue.global(qos: .userInitiated).async {
                clearStarted.signal()
                handleBits.update(nil)
                clearProbe.markClearCompleted()
                clearCompleted.signal()
            }

            clearStarted.wait()
            #expect(!clearProbe.clearCompleted)
        }

        let clearCompletionResult = clearCompleted.wait(timeout: .now() + 1)
        #expect(clearCompletionResult == .success)
    }

    @Test("pushes lifecycle focus changes to Ghostty")
    func focusSynchronizer_pushesLifecycleFocusChangesToGhostty() async {
        let appLifecycleStore = AppLifecycleAtom()
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
        let initialStore = AppLifecycleAtom()
        let secondStore = AppLifecycleAtom()
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
