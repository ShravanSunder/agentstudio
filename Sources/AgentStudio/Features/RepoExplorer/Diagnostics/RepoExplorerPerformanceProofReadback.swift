import Foundation

package struct RepoExplorerPerformanceProofReadback: Equatable, Sendable {
    package enum FocusDisposition: String, Equatable, Sendable {
        case filterFocused = "filter_focused"
        case notFocused = "not_focused"
    }

    package enum AccessibilityDisposition: String, Equatable, Sendable {
        case ready
        case unavailable
    }

    package let semanticGeneration: Int
    package let acknowledgedRevision: UInt64
    package let visibleGeneration: UInt64
    package let representedRowCount: Int
    package let groupingMode: RepoExplorerGroupingMode
    package let queryIsEmpty: Bool
    package let isDemanded: Bool
    package let presentationIsReady: Bool
    package let focusDisposition: FocusDisposition
    package let accessibilityDisposition: AccessibilityDisposition
}
