import Foundation
import Observation
import SwiftUI

/// Owns the transient "closing" state for pane-arrange close interactions.
///
/// This is intentionally not a command plane. It only delays the existing close
/// action long enough for the pane to show fast feedback before removal.
@MainActor
@Observable
final class PaneCloseTransitionCoordinator {
    private let clock: any Clock<Duration>
    private var pendingCloseTasks: [UUID: Task<Void, Never>] = [:]

    private(set) var closingPaneIds: Set<UUID> = []

    init(clock: any Clock<Duration> = ContinuousClock()) {
        self.clock = clock
    }

    isolated deinit {
        for task in pendingCloseTasks.values {
            task.cancel()
        }
        pendingCloseTasks.removeAll()
    }

    func beginClosingPane(
        _ paneId: UUID,
        delay: Duration = .milliseconds(120),
        performClose: @escaping @MainActor () -> Void
    ) {
        guard closingPaneIds.insert(paneId).inserted else { return }

        let sleepClock = self.clock
        let task = Task { [weak self] in
            do {
                try await sleepClock.sleep(for: delay)
            } catch {
                await MainActor.run { [weak self] in
                    self?.finishClosingPane(paneId)
                }
                return
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                withAnimation(.easeOut(duration: AppStyle.animationFast)) {
                    performClose()
                }
                self.finishClosingPane(paneId)
            }
        }

        pendingCloseTasks[paneId] = task
    }

    private func finishClosingPane(_ paneId: UUID) {
        closingPaneIds.remove(paneId)
        pendingCloseTasks[paneId] = nil
    }
}
