import AgentStudioCore
import AgentStudioInfrastructure
import Foundation

@MainActor
enum PanePullRequestToolbarActionFactory {
    private struct Presentation {
        let accessibilityLabel: String
        let tooltip: String
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

        let pullRequestFacts = GitHubWebviewLaunchResolver.pullRequestFacts(
            for: paneId,
            store: store,
            repoCache: repoCache
        )
        let exactPullRequestURL = pullRequestFacts?.exactOpenURL
        let presentation = presentation(for: pullRequestFacts)
        let isEnabled = exactPullRequestURL != nil
        return PaneSurfaceToolbarAction(
            state: PaneSurfaceToolbarAction.State(
                label: presentation.accessibilityLabel,
                accessibilityIdentifier: "paneSurfaceToolbar.pullRequest",
                icon: presentation.icon,
                tooltip: ControlTooltipRenderValue(
                    text: presentation.tooltip,
                    shortcutDisplayText: nil
                ),
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
        for pullRequestFacts: PullRequestFacts?
    ) -> Presentation {
        guard pullRequestFacts?.exactOpenURL != nil else {
            let actionSpec = LocalActionSpec.openPullRequest.actionSpec
            return Presentation(
                accessibilityLabel: actionSpec.label,
                tooltip: actionSpec.controlTooltipRenderValue(
                    provenance: .localAction(rawValue: "openPullRequest")
                ).text,
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

        let icon: CommandIcon =
            readiness?.isDraft == true
            ? .octicon(.gitPullRequestDraft)
            : .octicon(.gitPullRequest)
        return Presentation(
            accessibilityLabel: (["Open PR"] + statusDescriptions.map { $0.lowercased() })
                .joined(separator: ", "),
            tooltip: (["Open PR"] + statusDescriptions).joined(separator: " — "),
            icon: icon,
            iconStatusTone: iconStatusTone
        )
    }
}
