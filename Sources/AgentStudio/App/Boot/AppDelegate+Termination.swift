import AppKit
import Foundation

private let terminationTraceDrainTimeout: Duration = .seconds(2)

private final class TerminationDrainCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false

    func resume(_ continuation: CheckedContinuation<Bool, Never>, value: Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else { return }
        didResume = true
        continuation.resume(returning: value)
    }
}

extension AppDelegate {
    func flushApplicationStateBeforeTermination(store: WorkspaceStore) async {
        do {
            try repoCacheStore.flush(for: store.metadataAtom.workspaceId)
        } catch {
            appLogger.warning("Workspace cache flush failed at termination: \(error.localizedDescription)")
        }

        do {
            try sidebarCacheStore.flush(for: store.metadataAtom.workspaceId)
        } catch {
            appLogger.warning("Sidebar cache flush failed at termination: \(error.localizedDescription)")
        }

        do {
            try uiStateStore.flush(for: store.metadataAtom.workspaceId)
        } catch {
            appLogger.warning("Workspace UI flush failed at termination: \(error.localizedDescription)")
        }

        inboxNotificationRouter?.stop()
        inboxPaneFocusTracker?.stop()
        await stopTerminalActivityRouterBeforeTermination()

        // Always flush on quit — the pre-persist hook syncs runtime webview state
        // back to the pane model, so this must run even when isDirty == false.
        // Run it before inbox flush so any save-failure recovery event can be
        // persisted with the rest of the notification log.
        if !store.flush() {
            appLogger.warning("Workspace flush failed at termination")
        }

        do {
            try await inboxNotificationStore?.save()
        } catch {
            appLogger.warning("Inbox notification flush failed at termination: \(error.localizedDescription)")
        }
    }

    private func stopTerminalActivityRouterBeforeTermination() async {
        guard let terminalActivityRouter else { return }
        let didDrain = await withCheckedContinuation { continuation in
            let completion = TerminationDrainCompletion()
            Task { @MainActor in
                await terminalActivityRouter.stop()
                completion.resume(continuation, value: true)
            }
            Task {
                try? await Task.sleep(for: terminationTraceDrainTimeout)
                completion.resume(continuation, value: false)
            }
        }
        if !didDrain {
            appLogger.warning(
                "Terminal activity trace drain timed out at termination; continuing shutdown")
        }
    }
}
