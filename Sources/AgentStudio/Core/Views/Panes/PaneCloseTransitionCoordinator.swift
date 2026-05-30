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
    private let delay: AsyncDelay
    private var pendingCloseTasks: [UUID: Task<Void, Never>] = [:]

    private(set) var closingPaneIds: Set<UUID> = []

    init(clock: (any Clock<Duration> & Sendable)? = nil) {
        delay = clock.map(AsyncDelay.clock) ?? .taskSleep
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

        let delayScheduler = self.delay
        let task = Task { [weak self] in
            do {
                try await delayScheduler.wait(delay)
            } catch {
                await MainActor.run { [weak self] in
                    self?.finishClosingPane(paneId)
                }
                return
            }

            await MainActor.run { [weak self] in
                guard let self else { return }
                withAnimation(.easeOut(duration: AppStyles.General.Animation.fast)) {
                    performClose()
                }
                self.finishClosingPane(paneId)
            }
        }

        pendingCloseTasks[paneId] = task
    }

    /// Cancel any pending close transition for the given pane id.
    /// Used by undo to prevent a scheduled performClose from firing after
    /// the pane has already been restored.
    func cancelCloseTransition(_ paneId: UUID) {
        guard let task = pendingCloseTasks.removeValue(forKey: paneId) else { return }
        task.cancel()
        closingPaneIds.remove(paneId)
    }

    private func finishClosingPane(_ paneId: UUID) {
        closingPaneIds.remove(paneId)
        pendingCloseTasks[paneId] = nil
    }
}
