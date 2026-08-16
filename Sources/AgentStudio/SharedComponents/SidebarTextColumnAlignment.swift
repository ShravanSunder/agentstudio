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
            dimensions[.leading] + AppStyles.Shell.Sidebar.textColumnLeadingInset
        }
    }

    package func sidebarTextColumnGuide() -> some View {
        alignmentGuide(.sidebarTextColumn) { dimensions in
            dimensions[.leading]
        }
    }
}
