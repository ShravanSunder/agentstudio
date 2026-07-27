import AgentStudioInfrastructure
import SwiftUI

package enum SidebarSurfaceBackground: Equatable {
    case shellChrome
    case windowBackgroundColor

    var nsColor: NSColor {
        switch self {
        case .shellChrome:
            return AppStyles.Shell.TabBar.titlebarBackground
        case .windowBackgroundColor:
            return .windowBackgroundColor
        }
    }

    package var color: Color {
        Color(nsColor: nsColor)
    }
}

package struct SidebarSurfaceChromePolicy: Equatable {
    let minimumWidth: CGFloat
    let background: SidebarSurfaceBackground
    let shadowOpacity: CGFloat
    let shadowRadius: CGFloat
    let shadowOffsetX: CGFloat
    let shadowOffsetY: CGFloat

    static let repoMatched = Self(
        minimumWidth: AppStyles.Shell.Sidebar.minimumWidth,
        background: .shellChrome,
        shadowOpacity: AppStyles.Shell.Sidebar.shadowOpacity,
        shadowRadius: AppStyles.Shell.Sidebar.shadowRadius,
        shadowOffsetX: AppStyles.Shell.Sidebar.shadowOffsetX,
        shadowOffsetY: AppStyles.Shell.Sidebar.shadowOffsetY
    )
}

package enum SidebarSurfaceListPolicy: Equatable {
    case nativeSidebarList
}

package enum SidebarRowChromePolicy: Equatable {
    case sidebarRowShell
}

package enum SidebarHeaderChromePolicy: Equatable {
    case plainSectionHeader
    case repoGroupHeader
    case sourceGroupHeader
}

package struct SidebarSurfaceChrome<Content: View>: View {
    package static var policy: SidebarSurfaceChromePolicy {
        .repoMatched
    }

    private let content: Content

    package init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    package var body: some View {
        let policy = Self.policy
        content
            .frame(minWidth: policy.minimumWidth)
            .background(policy.background.color)
            .shadow(
                color: .black.opacity(Double(policy.shadowOpacity)),
                radius: policy.shadowRadius,
                x: policy.shadowOffsetX,
                y: policy.shadowOffsetY
            )
    }
}

extension View {
    @ViewBuilder
    package func sidebarSurfaceListStyle(_ policy: SidebarSurfaceListPolicy) -> some View {
        switch policy {
        case .nativeSidebarList:
            self.listStyle(.sidebar)
        }
    }
}
