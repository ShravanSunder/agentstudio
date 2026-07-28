import SwiftUI

enum ManagementOrdinalShortcutHintVariant: Equatable {
    case paneOverlay
    case collapsedBar
}

enum ManagementShortcutBadgeContent: Equatable {
    case ordinal(Int)
    case minimized

    var ordinal: Int? {
        guard case .ordinal(let ordinal) = self else { return nil }
        return ordinal
    }

    var systemImageName: String? {
        guard case .minimized = self else { return nil }
        return "eye.slash.fill"
    }
}

enum ManagementOrdinalShortcutHintPaint: Equatable {
    case black(opacity: CGFloat)
    case white(opacity: CGFloat)
    case secondary(opacity: CGFloat)

    var color: Color {
        switch self {
        case .black(let opacity):
            Color.black.opacity(opacity)
        case .white(let opacity):
            Color.white.opacity(opacity)
        case .secondary(let opacity):
            Color.secondary.opacity(opacity)
        }
    }
}

struct ManagementOrdinalShortcutHintStyle: Equatable {
    let foreground: ManagementOrdinalShortcutHintPaint
    let background: ManagementOrdinalShortcutHintPaint

    static func resolve(variant: ManagementOrdinalShortcutHintVariant) -> Self {
        switch variant {
        case .paneOverlay:
            return Self(
                foreground: .white(opacity: AppStyles.Shell.ManagementLayer.iconOpacity(isHovered: false)),
                background: .black(opacity: AppStyles.Shell.ManagementLayer.backgroundOpacity(isHovered: false))
            )
        case .collapsedBar:
            return Self(
                foreground: .secondary(opacity: AppStyles.Shell.ManagementLayer.collapsedBarOrdinalForegroundOpacity),
                background: .white(opacity: AppStyles.General.Fill.muted)
            )
        }
    }
}

struct ManagementOrdinalShortcutHint: View {
    let ordinal: Int
    let variant: ManagementOrdinalShortcutHintVariant

    init(
        ordinal: Int,
        variant: ManagementOrdinalShortcutHintVariant = .paneOverlay
    ) {
        self.ordinal = ordinal
        self.variant = variant
    }

    var body: some View {
        ManagementShortcutBadge(
            content: .ordinal(ordinal),
            variant: variant
        )
    }
}

struct ManagementMinimizedPaneHint: View {
    var body: some View {
        ManagementShortcutBadge(
            content: .minimized,
            variant: .collapsedBar
        )
    }
}

private struct ManagementShortcutBadge: View {
    let content: ManagementShortcutBadgeContent
    let variant: ManagementOrdinalShortcutHintVariant

    var body: some View {
        let style = ManagementOrdinalShortcutHintStyle.resolve(variant: variant)

        Group {
            if let ordinal = content.ordinal {
                Text("\(ordinal)")
                    .monospacedDigit()
            } else if let systemImageName = content.systemImageName {
                Image(systemName: systemImageName)
            }
        }
        .font(
            .system(
                size: AppStyles.Shell.ManagementLayer.actionIconSize,
                weight: .bold,
                design: .rounded
            )
        )
        .foregroundStyle(style.foreground.color)
        .frame(
            width: AppStyles.Shell.ManagementLayer.actionSize,
            height: AppStyles.Shell.ManagementLayer.actionSize
        )
        .background(
            Circle()
                .fill(style.background.color)
        )
        .contentShape(Circle())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
