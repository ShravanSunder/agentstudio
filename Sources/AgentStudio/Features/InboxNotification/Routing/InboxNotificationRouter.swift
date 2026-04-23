import Foundation
import os.log

private let inboxNotificationRouterLogger = Logger(
    subsystem: "com.agentstudio",
    category: "InboxNotificationRouter"
)

@MainActor
final class InboxNotificationRouter {
    private let bus: EventBus<RuntimeEnvelope>
    private let inboxAtom: InboxNotificationAtom
    private let prefsAtom: InboxNotificationPrefsAtom
    private let paneAtom: WorkspacePaneAtom
    private let tabLayout: WorkspaceTabLayoutAtom
    private let attendedPane: AttendedPaneAtom
    private let focusTracker: PaneFocusTracker

    private var busTask: Task<Void, Never>?
    private var focusTask: Task<Void, Never>?
    private var sandboxHealthWasHealthyByPaneId: [UUID: Bool] = [:]

    init(
        bus: EventBus<RuntimeEnvelope>,
        inboxAtom: InboxNotificationAtom,
        prefsAtom: InboxNotificationPrefsAtom,
        paneAtom: WorkspacePaneAtom,
        tabLayout: WorkspaceTabLayoutAtom,
        attendedPane: AttendedPaneAtom,
        focusTracker: PaneFocusTracker
    ) {
        self.bus = bus
        self.inboxAtom = inboxAtom
        self.prefsAtom = prefsAtom
        self.paneAtom = paneAtom
        self.tabLayout = tabLayout
        self.attendedPane = attendedPane
        self.focusTracker = focusTracker
    }

    func stop() {
        busTask?.cancel()
        busTask = nil
        focusTask?.cancel()
        focusTask = nil
        sandboxHealthWasHealthyByPaneId.removeAll()
    }

    func start() async {
        guard busTask == nil, focusTask == nil else { return }

        let stream = await bus.subscribe()
        busTask = Task { @MainActor [weak self] in
            for await envelope in stream {
                guard !Task.isCancelled else { return }
                guard let self, !Task.isCancelled else { return }
                self.handle(envelope)
            }
        }

        focusTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await paneId in self.focusTracker.focusGainedStream {
                guard !Task.isCancelled else { return }
                self.inboxAtom.markRead(paneId: paneId)
                self.inboxAtom.dismissFromDrawer(paneId: paneId)
            }
        }
    }

    private func handle(_ envelope: RuntimeEnvelope) {
        guard case .pane(let paneEnvelope) = envelope else { return }
        guard let kind = classify(paneEnvelope) else { return }

        let paneId = paneEnvelope.paneId.uuid
        let resolvedContext = resolveContext(for: paneId)
        let notification = InboxNotification(
            id: UUID(),
            timestamp: Date(),
            kind: kind,
            title: title(for: paneEnvelope.event),
            body: body(for: paneEnvelope.event),
            source: .pane(
                .init(
                    paneId: paneId,
                    tabId: resolvedContext?.tabId,
                    repoId: resolvedContext?.repoId,
                    repoName: resolvedContext?.repoName,
                    worktreeId: resolvedContext?.worktreeId,
                    worktreeName: resolvedContext?.worktreeName,
                    branchName: resolvedContext?.branchName
                )
            ),
            isRead: false,
            isDismissedFromDrawer: false
        )
        inboxAtom.append(notification)
    }

    private func classify(_ envelope: PaneEnvelope) -> InboxNotificationKind? {
        switch envelope.event {
        case .terminal(.desktopNotificationRequested):
            return .agentDesktopNotification
        case .agentNotificationRequested:
            return .agentRpc
        case .terminal(.bellRang):
            return prefsAtom.bellEnabled ? .bellRang : nil
        case .terminal(.commandFinished(_, let duration)):
            // Skip the pane the user is actively attending; the inbox is for unattended work.
            guard envelope.paneId.uuid != attendedPane.attendedPaneId else { return nil }
            guard duration >= AppPolicies.InboxNotification.commandFinishedMinDurationSeconds else { return nil }
            return .commandFinished
        case .artifact(.approvalRequested):
            return .approvalRequested
        case .security(.networkEgressBlocked),
            .security(.filesystemAccessDenied),
            .security(.secretAccessed),
            .security(.processSpawnBlocked):
            return .securityEvent
        case .security(.sandboxHealthChanged(let healthy)):
            let paneId = envelope.paneId.uuid
            let wasHealthy = sandboxHealthWasHealthyByPaneId[paneId, default: true]
            // Health is edge-triggered per pane so one unhealthy runtime does not mute another.
            let shouldNotify = wasHealthy && !healthy
            sandboxHealthWasHealthyByPaneId[paneId] = healthy
            return shouldNotify ? .securityEvent : nil
        default:
            inboxNotificationRouterLogger.debug(
                "Ignoring unclassified inbox event: \(String(describing: envelope.event), privacy: .public)"
            )
            return nil
        }
    }

    private func title(for event: PaneRuntimeEvent) -> String {
        switch event {
        case .terminal(.desktopNotificationRequested(let title, _)):
            return title
        case .agentNotificationRequested(let title, _):
            return title
        case .terminal(.bellRang):
            return "Bell"
        case .terminal(.commandFinished(let exitCode, _)):
            return exitCode == 0 ? "Command finished" : "Command failed (exit \(exitCode))"
        case .artifact(.approvalRequested):
            return "Approval requested"
        case .security(.networkEgressBlocked):
            return "Network egress blocked"
        case .security(.filesystemAccessDenied):
            return "Filesystem access denied"
        case .security(.secretAccessed):
            return "Secret accessed"
        case .security(.processSpawnBlocked):
            return "Process spawn blocked"
        case .security(.sandboxHealthChanged):
            return "Sandbox unhealthy"
        default:
            return "Notification"
        }
    }

    private func body(for event: PaneRuntimeEvent) -> String? {
        switch event {
        case .terminal(.desktopNotificationRequested(_, let body)):
            return body.isEmpty ? nil : body
        case .agentNotificationRequested(_, let body):
            return body?.isEmpty == true ? nil : body
        case .terminal(.commandFinished(let exitCode, let duration)):
            return "exit \(exitCode) · \(formattedDuration(duration))"
        case .artifact(.approvalRequested(let request)):
            return request.summary
        case .security(.networkEgressBlocked(let destination, let rule)):
            return "\(destination) · \(rule)"
        case .security(.filesystemAccessDenied(let path, let operation)):
            return "\(operation) · \(path)"
        case .security(.secretAccessed(let secretId, let consumerId)):
            return "\(secretId) · \(consumerId)"
        case .security(.processSpawnBlocked(let command, let rule)):
            return "\(command) · \(rule)"
        case .security(.sandboxHealthChanged(let healthy)):
            return healthy ? nil : "health transitioned to unhealthy"
        default:
            return nil
        }
    }

    private func formattedDuration(_ seconds: UInt64) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    private func resolveContext(for paneId: UUID) -> ResolvedPaneContext? {
        guard let pane = paneAtom.pane(paneId) else { return nil }
        return ResolvedPaneContext(
            tabId: tabLayout.tabContaining(paneId: paneId)?.id,
            repoId: pane.repoId,
            repoName: pane.metadata.repoName,
            worktreeId: pane.worktreeId,
            worktreeName: pane.metadata.worktreeName,
            branchName: pane.metadata.checkoutRef
        )
    }
}

private struct ResolvedPaneContext {
    let tabId: UUID?
    let repoId: UUID?
    let repoName: String?
    let worktreeId: UUID?
    let worktreeName: String?
    let branchName: String?
}
