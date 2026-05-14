import SwiftUI

enum SidebarSurfaceBackground: Equatable {
    case windowBackgroundColor

    var color: Color {
        switch self {
        case .windowBackgroundColor:
            return Color(nsColor: .windowBackgroundColor)
        }
    }
}

struct SidebarSurfaceChromePolicy: Equatable {
    let minimumWidth: CGFloat
    let background: SidebarSurfaceBackground
    let shadowOpacity: CGFloat
    let shadowRadius: CGFloat
    let shadowOffsetX: CGFloat
    let shadowOffsetY: CGFloat

    static let repoMatched = Self(
        minimumWidth: AppStyles.Shell.Sidebar.minimumWidth,
        background: .windowBackgroundColor,
        shadowOpacity: AppStyles.Shell.Sidebar.shadowOpacity,
        shadowRadius: AppStyles.Shell.Sidebar.shadowRadius,
        shadowOffsetX: AppStyles.Shell.Sidebar.shadowOffsetX,
        shadowOffsetY: AppStyles.Shell.Sidebar.shadowOffsetY
    )
}

enum SidebarSurfaceListPolicy: Equatable {
    case nativeSidebarList
}

enum SidebarRowChromePolicy: Equatable {
    case sidebarRowShell
}

enum SidebarHeaderChromePolicy: Equatable {
    case plainSectionHeader
    case repoGroupHeader
}

struct SidebarSurfaceChrome<Content: View>: View {
    static var policy: SidebarSurfaceChromePolicy {
        .repoMatched
    }

    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
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
    func sidebarSurfaceListStyle(_ policy: SidebarSurfaceListPolicy) -> some View {
        switch policy {
        case .nativeSidebarList:
            self.listStyle(.sidebar)
        }
    }
}
