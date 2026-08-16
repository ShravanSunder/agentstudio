import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

@MainActor
enum PanePullRequestToolbarActionFactory {
    private struct Presentation {
        let accessibilityLabel: String
        let tooltip: ControlTooltipRenderValue
        let icon: CommandIcon
        let iconStatusTone: PaneSurfaceToolbarAction.IconStatusTone?
    }

    static func make(
        paneId: UUID,
        store: WorkspaceStore,
        repoCache: RepoCacheAtom,
        openExternalURL: @escaping @MainActor @Sendable (URL) -> Bool
    ) -> PaneSurfaceToolbarAction? {
        guard
            GitHubWebviewLaunchResolver.hasResolvableWorktreeContext(
                for: paneId,
                store: store
            )
        else { return nil }

        let actionSpec = LocalActionSpec.openPullRequest.actionSpec
        let pullRequestFacts = GitHubWebviewLaunchResolver.pullRequestFacts(
            for: paneId,
            store: store,
            repoCache: repoCache
        )
        let exactPullRequestURL = pullRequestFacts?.exactOpenURL
        let presentation = presentation(for: pullRequestFacts, actionSpec: actionSpec)
        let isEnabled = exactPullRequestURL != nil
        return PaneSurfaceToolbarAction(
            state: PaneSurfaceToolbarAction.State(
                label: presentation.accessibilityLabel,
                accessibilityIdentifier: "paneSurfaceToolbar.pullRequest",
                icon: presentation.icon,
                tooltip: presentation.tooltip,
                isEnabled: isEnabled,
                isSelected: false,
                selectionEmphasis: .standard,
                iconStatusTone: isEnabled ? presentation.iconStatusTone : nil
            ),
            perform: {
                guard let exactPullRequestURL else { return }
                _ = openExternalURL(exactPullRequestURL)
            }
        )
    }

    private static func presentation(
        for pullRequestFacts: PullRequestFacts?,
        actionSpec: ActionSpec
    ) -> Presentation {
        guard pullRequestFacts?.exactOpenURL != nil else {
            return Presentation(
                accessibilityLabel: actionSpec.label,
                tooltip: actionSpec.controlTooltipRenderValue(
                    provenance: .localAction(rawValue: "openPullRequest")
                ),
                icon: actionSpec.icon,
                iconStatusTone: nil
            )
        }
        let readiness = pullRequestFacts?.exactReadiness
        let checkStatus = readiness?.checkStatus ?? .unknown
        let checkDescription: String
        let iconStatusTone: PaneSurfaceToolbarAction.IconStatusTone?
        switch checkStatus {
        case .passed:
            checkDescription = "Checks passed"
            iconStatusTone = .success
        case .running:
            checkDescription = "Checks running"
            iconStatusTone = .warning
        case .failed:
            checkDescription = "Checks failed"
            iconStatusTone = .danger
        case .unknown:
            checkDescription = "Checks unknown"
            iconStatusTone = nil
        }

        var statusDescriptions = [checkDescription]
        if readiness?.isDraft == true {
            statusDescriptions.append("Draft")
        }
        switch readiness?.reviewStatus {
        case .changesRequested:
            statusDescriptions.append("Changes requested")
        case .reviewRequired:
            statusDescriptions.append("Review required")
        case .approved, .unknown, nil:
            break
        }
        switch readiness?.mergeState {
        case .blocked:
            statusDescriptions.append("Merge blocked")
        case .behind:
            statusDescriptions.append("Branch behind")
        case .dirty:
            statusDescriptions.append("Conflicts")
        case .hasHooks:
            statusDescriptions.append("Merge hooks pending")
        case .unstable:
            statusDescriptions.append("Merge unstable")
        case .clean, .draft, .unknown, nil:
            if readiness?.mergeability == .conflicting {
                statusDescriptions.append("Conflicts")
            }
        }

        let baseIcon = actionSpec.icon
        let icon: CommandIcon =
            readiness?.isDraft == true
            ? .octicon(.gitPullRequestDraft)
            : baseIcon
        let tooltipText = ([actionSpec.label] + statusDescriptions).joined(separator: " — ")
        return Presentation(
            accessibilityLabel: ([actionSpec.label] + statusDescriptions.map { $0.lowercased() })
                .joined(separator: ", "),
            tooltip: actionSpec.controlTooltipRenderValue(
                provenance: .localAction(rawValue: "openPullRequest"),
                textOverride: tooltipText
            ),
            icon: icon,
            iconStatusTone: iconStatusTone
        )
    }
}
