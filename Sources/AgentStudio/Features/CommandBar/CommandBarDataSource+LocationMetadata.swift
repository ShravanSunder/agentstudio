import Foundation

@MainActor
extension CommandBarDataSource {
    static func tabLocationSubtitle(
        tabIndex: Int,
        paneCount: Int?,
        isActive: Bool
    ) -> String {
        var parts = ["Tab \(tabIndex + 1)"]
        if let paneCount, paneCount > 1 {
            parts.append("\(paneCount) panes")
        }
        if isActive {
            parts.append("Active")
        }
        return parts.joined(separator: " · ")
    }

    static func paneLocationSubtitle(
        tabTitle: String?,
        tabIndex: Int,
        paneIndex: Int,
        isActive: Bool
    ) -> String {
        var parts: [String] = []
        if let tabTitle {
            parts.append(tabTitle)
        }
        parts.append("Tab \(tabIndex + 1)")
        parts.append("Pane \(paneIndex + 1)")
        if isActive {
            parts.append("Active")
        }
        return parts.joined(separator: " · ")
    }
}
