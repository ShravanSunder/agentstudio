import Foundation

@MainActor
enum InboxNotificationPresentation {
    struct NotificationText: Sendable, Equatable {
        let title: String
        let body: String?
    }

    struct ResolvedPaneContext {
        let tabId: UUID?
        let tabDisplayLabel: String?
        let tabOrdinal: Int?
        let repoId: UUID?
        let repoName: String?
        let worktreeId: UUID?
        let worktreeName: String?
        let branchName: String?
        let paneDisplayLabel: String?
        let paneOrdinal: Int?
        let paneRole: InboxNotification.PaneSource.PaneRole
        let parentPaneId: UUID?
        let parentPaneDisplayLabel: String?
        let parentPaneOrdinal: Int?
        let drawerOrdinal: Int?
        let runtimeDisplayLabel: String?
    }

    static func notificationText(for event: PaneRuntimeEvent) -> NotificationText {
        switch event {
        case .terminal(.desktopNotificationRequested(let title, let body)):
            return notificationText(
                title: title,
                body: body,
                fallbackTitle: "Desktop notification"
            )
        case .agentNotificationRequested(let title, let body):
            return notificationText(
                title: title,
                body: body,
                fallbackTitle: "Agent notification"
            )
        case .terminal(.bellRang):
            return .init(title: "Bell", body: nil)
        case .terminal(.commandFinished(let exitCode, let duration)):
            let title = exitCode == 0 ? "Command finished" : "Command failed"
            return .init(title: title, body: "exit \(exitCode) · \(formattedDuration(duration))")
        case .terminal(.secureInputChanged):
            return .init(title: "Secure input requested", body: secureInputBody(for: event))
        case .terminal(.progressReportUpdated):
            return .init(title: "Terminal progress error", body: progressBody(for: event))
        case .terminal(.rendererHealthChanged):
            return .init(title: "Terminal renderer unhealthy", body: rendererHealthBody(for: event))
        case .artifact(.approvalRequested):
            return .init(title: "Approval requested", body: approvalBody(for: event))
        case .security(.networkEgressBlocked):
            return .init(title: "Network egress blocked", body: securityBody(for: event))
        case .security(.filesystemAccessDenied):
            return .init(title: "Filesystem access denied", body: securityBody(for: event))
        case .security(.secretAccessed):
            return .init(title: "Secret accessed", body: securityBody(for: event))
        case .security(.processSpawnBlocked):
            return .init(title: "Process spawn blocked", body: securityBody(for: event))
        case .security(.sandboxHealthChanged):
            return .init(title: "Sandbox unhealthy", body: securityBody(for: event))
        default:
            return .init(title: "Notification", body: nil)
        }
    }

    static func claimSemantic(for event: PaneRuntimeEvent) -> InboxNotificationClaimSemantic {
        switch event {
        case .terminal(.desktopNotificationRequested):
            return .desktopNotification
        case .agentNotificationRequested:
            return .agentRpc
        case .terminal(.bellRang):
            return .bell
        case .terminal(.commandFinished):
            return .commandFinished
        case .terminal(.secureInputChanged):
            return .secureInput
        case .terminal(.progressReportUpdated):
            return .progressError
        case .terminal(.rendererHealthChanged):
            return .rendererUnhealthy
        case .artifact(.approvalRequested):
            return .approvalRequested
        case .security(.networkEgressBlocked),
            .security(.filesystemAccessDenied),
            .security(.secretAccessed),
            .security(.processSpawnBlocked),
            .security(.sandboxHealthChanged):
            return .securityEvent
        case .terminalActivity(.unseenActivitySettled):
            return .unseenActivity
        case .terminalActivity(.agentSettledActivityPromoted):
            return .agentSettled
        case .terminalActivity(.agentSettledActivityRevoked):
            return .unseenActivity
        default:
            return .agentRpc
        }
    }

    static func paneSource(
        paneId: UUID,
        resolvedContext: ResolvedPaneContext?
    ) -> InboxNotification.PaneSource {
        .init(
            paneId: paneId,
            tabId: resolvedContext?.tabId,
            tabDisplayLabel: resolvedContext?.tabDisplayLabel,
            tabOrdinal: resolvedContext?.tabOrdinal,
            repoId: resolvedContext?.repoId,
            repoName: resolvedContext?.repoName,
            worktreeId: resolvedContext?.worktreeId,
            worktreeName: resolvedContext?.worktreeName,
            branchName: resolvedContext?.branchName,
            paneDisplayLabel: resolvedContext?.paneDisplayLabel,
            paneOrdinal: resolvedContext?.paneOrdinal,
            paneRole: resolvedContext?.paneRole ?? .main,
            parentPaneId: resolvedContext?.parentPaneId,
            parentPaneDisplayLabel: resolvedContext?.parentPaneDisplayLabel,
            parentPaneOrdinal: resolvedContext?.parentPaneOrdinal,
            drawerOrdinal: resolvedContext?.drawerOrdinal,
            runtimeDisplayLabel: resolvedContext?.runtimeDisplayLabel
        )
    }

    static func resolveContext(
        for paneId: UUID,
        paneAtom: WorkspacePaneAtom,
        tabLayout: WorkspaceTabLayoutAtom
    ) -> ResolvedPaneContext? {
        guard let pane = paneAtom.pane(paneId) else { return nil }
        let owningPaneId = pane.parentPaneId ?? paneId
        let tab = tabLayout.tabContaining(paneId: owningPaneId)
        let tabIndex = tab.flatMap { tab in
            tabLayout.tabs.firstIndex { $0.id == tab.id }
        }
        let owningPaneIndex = tab.flatMap { tab in
            tab.activePaneIds.firstIndex(of: owningPaneId)
        }
        let parentPane = pane.parentPaneId.flatMap { paneAtom.pane($0) }
        return ResolvedPaneContext(
            tabId: tab?.id,
            tabDisplayLabel: tab.flatMap(Self.displayLabel(for:)),
            tabOrdinal: tabIndex.map { $0 + 1 },
            repoId: pane.repoId,
            repoName: pane.metadata.repoName,
            worktreeId: pane.worktreeId,
            worktreeName: pane.metadata.worktreeName,
            branchName: pane.metadata.checkoutRef,
            paneDisplayLabel: Self.displayLabel(for: pane),
            paneOrdinal: pane.isDrawerChild ? nil : owningPaneIndex.map { $0 + 1 },
            paneRole: pane.isDrawerChild ? .drawerChild : .main,
            parentPaneId: pane.parentPaneId,
            parentPaneDisplayLabel: parentPane.flatMap(Self.displayLabel(for:)),
            parentPaneOrdinal: pane.isDrawerChild ? owningPaneIndex.map { $0 + 1 } : nil,
            drawerOrdinal: drawerOrdinal(for: paneId, parentPane: parentPane),
            runtimeDisplayLabel: Self.runtimeDisplayLabel(for: pane)
        )
    }

    private static func notificationText(
        title: String,
        body: String?,
        fallbackTitle: String
    ) -> NotificationText {
        let normalizedTitle = title.trimmedNonEmpty
        let normalizedBody = body.trimmedNonEmpty
        if let normalizedTitle {
            let boundedText = InboxNotificationTextPolicy.bounded(title: normalizedTitle, body: normalizedBody)
            return .init(title: boundedText.title, body: boundedText.body)
        }
        if let normalizedBody {
            let boundedText = InboxNotificationTextPolicy.bounded(title: normalizedBody, body: nil)
            return .init(title: boundedText.title, body: nil)
        }
        return .init(title: fallbackTitle, body: nil)
    }

    private static func secureInputBody(for event: PaneRuntimeEvent) -> String? {
        guard case .terminal(.secureInputChanged(let isActive)) = event else { return nil }
        return isActive ? "terminal is waiting for hidden input" : nil
    }

    private static func progressBody(for event: PaneRuntimeEvent) -> String? {
        guard case .terminal(.progressReportUpdated(let progress)) = event else { return nil }
        guard let progress else { return nil }
        guard let percent = progress.percent else { return "progress error" }
        return "progress \(percent)%"
    }

    private static func rendererHealthBody(for event: PaneRuntimeEvent) -> String? {
        guard case .terminal(.rendererHealthChanged(let healthy)) = event else { return nil }
        return healthy ? nil : "renderer health transitioned to unhealthy"
    }

    private static func approvalBody(for event: PaneRuntimeEvent) -> String? {
        guard case .artifact(.approvalRequested(let request)) = event else { return nil }
        return InboxNotificationTextPolicy.approvalSummary(requestSummary: request.summary)
    }

    private static func securityBody(for event: PaneRuntimeEvent) -> String? {
        switch event {
        case .security(.networkEgressBlocked):
            return InboxNotificationTextPolicy.securitySummary(kind: .networkEgressBlocked)
        case .security(.filesystemAccessDenied(_, let operation)):
            return InboxNotificationTextPolicy.securitySummary(
                kind: .filesystemAccessDenied(operation: operation)
            )
        case .security(.secretAccessed):
            return InboxNotificationTextPolicy.securitySummary(kind: .secretAccessed)
        case .security(.processSpawnBlocked):
            return InboxNotificationTextPolicy.securitySummary(kind: .processSpawnBlocked)
        case .security(.sandboxHealthChanged(let healthy)):
            return healthy ? nil : "health transitioned to unhealthy"
        default:
            return nil
        }
    }

    private static func formattedDuration(_ nanoseconds: UInt64) -> String {
        let seconds = nanoseconds / 1_000_000_000
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        if minutes > 0 {
            return "\(minutes)m \(remainingSeconds)s"
        }
        return "\(remainingSeconds)s"
    }

    private static func drawerOrdinal(for paneId: UUID, parentPane: Pane?) -> Int? {
        guard let paneIds = parentPane?.drawer?.paneIds else { return nil }
        guard let index = paneIds.firstIndex(of: paneId) else { return nil }
        return index + 1
    }

    private static func displayLabel(for tab: Tab) -> String? {
        Tab.normalizedName(tab.name).trimmedNonEmpty
    }

    private static func displayLabel(for pane: Pane) -> String? {
        pane.metadata.title.trimmedNonEmpty
            ?? pane.metadata.worktreeName.trimmedNonEmpty
            ?? pane.metadata.checkoutRef.trimmedNonEmpty
            ?? runtimeDisplayLabel(for: pane)
    }

    private static func runtimeDisplayLabel(for pane: Pane) -> String {
        switch pane.content {
        case .terminal:
            return "Terminal"
        case .webview:
            return "Browser"
        case .bridgePanel(let state):
            switch state.panelKind {
            case .diffViewer:
                return "Diff"
            case .fileViewer:
                return "Files"
            }
        case .codeViewer:
            return "Code"
        case .unsupported(let content):
            return content.type.isEmpty ? "Pane" : content.type
        }
    }
}
