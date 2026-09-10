import Foundation

struct RepoExplorerObservationRegistration: Equatable, Sendable {
    let repositoryIDs: Set<UUID>
    let worktreeIDs: Set<UUID>
    let paneIDs: Set<UUID>
    let tabIDs: Set<UUID>
    let observesPanePresentation: Bool
    let observesAttention: Bool
    let observesTabPresentation: Bool

    static let hidden = Self(
        repositoryIDs: [],
        worktreeIDs: [],
        paneIDs: [],
        tabIDs: [],
        observesPanePresentation: false,
        observesAttention: false,
        observesTabPresentation: false
    )

    var requiresRecencyDeadline: Bool {
        observesPanePresentation && !paneIDs.isEmpty
    }

    static func make(
        isVisible: Bool,
        groupingMode: RepoExplorerGroupingMode,
        repositoryIDs: Set<UUID>,
        worktreeIDs: Set<UUID>,
        paneIDs: Set<UUID>,
        tabIDs: Set<UUID>
    ) -> Self {
        guard isVisible else { return .hidden }

        switch groupingMode {
        case .repo:
            return Self(
                repositoryIDs: repositoryIDs,
                worktreeIDs: worktreeIDs,
                paneIDs: [],
                tabIDs: [],
                observesPanePresentation: false,
                observesAttention: false,
                observesTabPresentation: false
            )
        case .pane:
            return Self(
                repositoryIDs: repositoryIDs,
                worktreeIDs: worktreeIDs,
                paneIDs: paneIDs,
                tabIDs: [],
                observesPanePresentation: true,
                observesAttention: true,
                observesTabPresentation: false
            )
        case .tab:
            return Self(
                repositoryIDs: repositoryIDs,
                worktreeIDs: worktreeIDs,
                paneIDs: paneIDs,
                tabIDs: tabIDs,
                observesPanePresentation: true,
                observesAttention: true,
                observesTabPresentation: true
            )
        }
    }
}
