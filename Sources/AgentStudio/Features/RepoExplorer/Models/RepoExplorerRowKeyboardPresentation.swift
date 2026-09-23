import AgentStudioInfrastructure

/// Row chrome is independent of materialized content and its height/reuse revisions.
struct RepoExplorerRowKeyboardPresentation: Equatable, Sendable {
    static let inactive = Self(isSelected: false, shortcutDisplay: nil)

    let isSelected: Bool
    let shortcutDisplay: ShortcutDisplayText?
}
