import AgentStudioInfrastructure
import SwiftUI

private struct SidebarTextColumnAlignmentID: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
        dimensions[.leading]
    }
}

extension HorizontalAlignment {
    package static let sidebarTextColumn = HorizontalAlignment(SidebarTextColumnAlignmentID.self)
}

extension View {
    package func sidebarIconLineTextColumnGuide() -> some View {
        alignmentGuide(.sidebarTextColumn) { dimensions in
            dimensions[.leading] + AppStyles.Shell.Sidebar.statusRowLeadingIndent
        }
    }

    /// Aligns a chips line so the FIRST chip's rendered content (its leading glyph/text, inside the
    /// pill's own horizontal padding) lands on the shared text column, not the pill's background edge.
    /// The chips-line leading edge is pulled left by the pill's own horizontal padding so the two
    /// constants can never drift apart; a bare, unpadded leading element (the pending-facts glyph) must
    /// compensate with matching leading padding of its own when it renders first.
    package func sidebarTextColumnGuide() -> some View {
        alignmentGuide(.sidebarTextColumn) { dimensions in
            dimensions[.leading] + AppStyles.Shell.Sidebar.chipHorizontalPadding
        }
    }
}
