import Foundation

/// Bounds actual in-flight cold starts (SR4; Program Design item 4): "A cold
/// start holds one of `AppPolicies.Restore.maximumConcurrentColdStarts`
/// start slots, from the moment its surface mounts until the slot settles
/// ... Further cold panes wait in the existing activation order (visible
/// first)." That ordering comes for free here: callers `acquire()` in the
/// same order `TerminalActivationScheduler` already admits panes (visible
/// first), and this gate serves waiters strictly in arrival order (FIFO).
///
/// Warm and unverified attaches never call this — they don't take slots.
///
/// A classic async counting semaphore. One instance for the whole app
/// session, constructed once at boot and threaded to every cold pane's
/// mount, mirroring `TerminalRestoreKindResolver`'s own lifetime.
package actor ColdStartSlotGate {
    private var availableSlotCount: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    package init(capacity: Int) {
        precondition(capacity > 0, "ColdStartSlotGate needs at least one slot")
        availableSlotCount = capacity
    }

    /// Waits for a free slot, then holds it — pairs with exactly one later
    /// `release()`. Waiters are served in the order they called `acquire()`.
    package func acquire() async {
        guard availableSlotCount > 0 else {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
            return
        }
        availableSlotCount -= 1
    }

    /// Settles the slot: hands it directly to the longest-waiting caller, or
    /// returns it to the pool when nobody is waiting. Called once a cold
    /// start's window ends — handed off, failed, unobservable, or the pane
    /// was retired or its activation cancelled while pending — never more
    /// than once per matching `acquire()`.
    package func release() {
        guard !waiters.isEmpty else {
            availableSlotCount += 1
            return
        }
        let nextWaiter = waiters.removeFirst()
        nextWaiter.resume()
    }

    /// Test-only observation of the pool's current state.
    package var availableSlotCountForTesting: Int { availableSlotCount }
    package var waitingCountForTesting: Int { waiters.count }
}
