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

    package func sidebarTextColumnGuide() -> some View {
        alignmentGuide(.sidebarTextColumn) { dimensions in
            dimensions[.leading]
        }
    }

    /// Aligns the first chip's pill edge with the shared text column. The pending-facts glyph remains
    /// an overlay in the dedicated leading icon gutter and does not shift the chip row.
    package func sidebarChipRowTextColumnGuide() -> some View {
        alignmentGuide(.sidebarTextColumn) { dimensions in
            dimensions[.leading]
        }
    }
}
