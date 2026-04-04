import AppKit
import SwiftUI

struct WorkspaceStatusChipsModel: Equatable {
    let branchStatus: GitBranchStatus
    let notificationCount: Int
}

struct WorkspaceStatusChipRow: View {
    let model: WorkspaceStatusChipsModel
    let accentColor: Color

    private var syncCounts: (ahead: String, behind: String) {
        switch model.branchStatus.syncState {
        case .synced:
            return ("0", "0")
        case .ahead(let count):
            return ("\(count)", "0")
        case .behind(let count):
            return ("0", "\(count)")
        case .diverged(let ahead, let behind):
            return ("\(ahead)", "\(behind)")
        case .noUpstream:
            return ("-", "-")
        case .unknown:
            return ("?", "?")
        }
    }

    private var hasSyncSignal: Bool {
        switch model.branchStatus.syncState {
        case .ahead(let count):
            return count > 0
        case .behind(let count):
            return count > 0
        case .diverged(let ahead, let behind):
            return ahead > 0 || behind > 0
        case .synced, .noUpstream, .unknown:
            return false
        }
    }

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipRowSpacing) {
            WorkspaceDiffChip(
                linesAdded: model.branchStatus.linesAdded,
                linesDeleted: model.branchStatus.linesDeleted,
                showsDirtyIndicator: model.branchStatus.isDirty,
                isMuted: model.branchStatus.linesAdded == 0 && model.branchStatus.linesDeleted == 0
            )

            WorkspaceStatusSyncChip(
                aheadText: syncCounts.ahead,
                behindText: syncCounts.behind,
                hasSyncSignal: hasSyncSignal
            )

            WorkspaceStatusChip(
                iconAsset: "octicon-git-pull-request",
                text: "\(model.branchStatus.prCount ?? 0)",
                style: (model.branchStatus.prCount ?? 0) > 0 ? .accent(accentColor) : .neutral
            )

            WorkspaceStatusChip(
                iconAsset: "octicon-bell",
                text: "\(model.notificationCount)",
                style: model.notificationCount > 0 ? .accent(accentColor) : .neutral
            )
        }
    }
}

struct WorkspaceStatusChip: View {
    enum Style {
        case neutral
        case info
        case danger
        case accent(Color)

        var foreground: Color {
            switch self {
            case .neutral:
                return .secondary
            case .info:
                return Color(red: 0.47, green: 0.69, blue: 0.96)
            case .danger:
                return Color(red: 0.93, green: 0.41, blue: 0.41)
            case .accent(let color):
                return color
            }
        }
    }

    let iconAsset: String
    let text: String?
    let style: Style

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipContentSpacing) {
            WorkspaceOcticonImage(name: iconAsset, size: AppStyle.sidebarChipIconSize)
            if let text {
                Text(text)
                    .font(.system(size: AppStyle.sidebarChipFontSize, weight: .medium).monospacedDigit())
                    .lineLimit(1)
            }
        }
        .padding(
            .horizontal,
            text == nil ? AppStyle.sidebarChipIconOnlyHorizontalPadding : AppStyle.sidebarChipHorizontalPadding
        )
        .padding(.vertical, AppStyle.sidebarChipVerticalPadding)
        .background(chipBackground)
        .foregroundStyle(style.foreground.opacity(AppStyle.sidebarChipForegroundOpacity))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }

    private var chipBackground: some View {
        Capsule()
            .fill(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
            .overlay(
                Capsule()
                    .fill(Color.black.opacity(AppStyle.sidebarChipMuteOverlayOpacity))
            )
    }
}

struct WorkspaceStatusSyncChip: View {
    let aheadText: String
    let behindText: String
    let hasSyncSignal: Bool

    private var effectiveStyle: WorkspaceStatusChip.Style {
        hasSyncSignal ? .info : .neutral
    }

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipContentSpacing) {
            HStack(spacing: AppStyle.sidebarSyncClusterSpacing) {
                WorkspaceOcticonImage(name: "octicon-arrow-up", size: AppStyle.sidebarSyncChipIconSize)
                Text(aheadText)
            }
            HStack(spacing: AppStyle.sidebarSyncClusterSpacing) {
                WorkspaceOcticonImage(name: "octicon-arrow-down", size: AppStyle.sidebarSyncChipIconSize)
                Text(behindText)
            }
        }
        .font(.system(size: AppStyle.sidebarChipFontSize, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, AppStyle.sidebarChipHorizontalPadding)
        .padding(.vertical, AppStyle.sidebarChipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyle.sidebarChipMuteOverlayOpacity))
                )
        )
        .foregroundStyle(effectiveStyle.foreground.opacity(AppStyle.sidebarChipForegroundOpacity))
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct WorkspaceDiffChip: View {
    let linesAdded: Int
    let linesDeleted: Int
    let showsDirtyIndicator: Bool
    let isMuted: Bool

    private var plusColor: Color {
        if isMuted {
            return WorkspaceStatusChip.Style.neutral.foreground.opacity(AppStyle.sidebarChipForegroundOpacity)
        }
        return Color(red: 0.42, green: 0.84, blue: 0.50).opacity(AppStyle.sidebarChipForegroundOpacity)
    }

    private var minusColor: Color {
        if isMuted {
            return WorkspaceStatusChip.Style.neutral.foreground.opacity(AppStyle.sidebarChipForegroundOpacity)
        }
        return Color(red: 0.93, green: 0.41, blue: 0.41).opacity(AppStyle.sidebarChipForegroundOpacity)
    }

    var body: some View {
        HStack(spacing: AppStyle.sidebarChipContentSpacing) {
            if showsDirtyIndicator {
                WorkspaceOcticonImage(name: "octicon-dot-fill", size: AppStyle.sidebarChipIconSize)
                    .foregroundStyle(
                        WorkspaceStatusChip.Style.danger.foreground.opacity(AppStyle.sidebarChipForegroundOpacity)
                    )
            }

            HStack(spacing: AppStyle.spacingTight) {
                Text("+\(linesAdded)")
                    .foregroundStyle(plusColor)
                Text("-\(linesDeleted)")
                    .foregroundStyle(minusColor)
            }
        }
        .font(.system(size: AppStyle.sidebarChipFontSize, weight: .medium).monospacedDigit())
        .lineLimit(1)
        .padding(.horizontal, AppStyle.sidebarChipHorizontalPadding)
        .padding(.vertical, AppStyle.sidebarChipVerticalPadding)
        .background(
            Capsule()
                .fill(Color.white.opacity(AppStyle.sidebarChipBackgroundOpacity))
                .overlay(
                    Capsule()
                        .fill(Color.black.opacity(AppStyle.sidebarChipMuteOverlayOpacity))
                )
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(AppStyle.sidebarChipBorderOpacity), lineWidth: 1)
        )
        .fixedSize(horizontal: true, vertical: true)
    }
}

struct WorkspaceOcticonImage: View {
    let name: String
    let size: CGFloat

    var body: some View {
        Group {
            if let image = WorkspaceOcticonLoader.shared.image(named: name) {
                Image(nsImage: image)
                    .renderingMode(.template)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "questionmark.square.dashed")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
    }
}

@MainActor
private final class WorkspaceOcticonLoader {
    static let shared = WorkspaceOcticonLoader()

    private var cache: [String: NSImage] = [:]

    private init() {}

    func image(named name: String) -> NSImage? {
        if let cached = cache[name] {
            return cached
        }

        let subdirectory = "SidebarIcons.xcassets/\(name).imageset"
        if let svgURL = Bundle.appResources.url(
            forResource: name,
            withExtension: "svg",
            subdirectory: subdirectory
        ),
            let image = NSImage(contentsOf: svgURL)
        {
            cache[name] = image
            return image
        }

        if let pdfURL = Bundle.appResources.url(
            forResource: name,
            withExtension: "pdf",
            subdirectory: subdirectory
        ),
            let image = NSImage(contentsOf: pdfURL)
        {
            cache[name] = image
            return image
        }

        return nil
    }
}
