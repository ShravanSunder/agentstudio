import SwiftUI

// MARK: - CommandBarShortcutBadge

/// Renders keyboard shortcut as individual key badges: [⌘] [W]
/// Linear-style: small rounded rectangles with SF Mono characters.
struct CommandBarShortcutBadge: View {
    enum Style {
        case row
        case footerCompact

        var spacing: CGFloat {
            switch self {
            case .row:
                return 2
            case .footerCompact:
                return 1
            }
        }

        var horizontalPadding: CGFloat {
            switch self {
            case .row:
                return 4
            case .footerCompact:
                return 3
            }
        }

        var verticalPadding: CGFloat {
            switch self {
            case .row:
                return 2
            case .footerCompact:
                return 1
            }
        }

        var cornerRadius: CGFloat {
            switch self {
            case .row:
                return 4
            case .footerCompact:
                return 3
            }
        }
    }

    let keys: [ShortcutKey]
    let style: Style

    init(keys: [ShortcutKey], style: Style = .row) {
        self.keys = keys
        self.style = style
    }

    var body: some View {
        HStack(spacing: style.spacing) {
            ForEach(keys) { key in
                Text(key.symbol)
                    .font(.system(size: AppStyle.textXs, weight: .medium, design: .monospaced))
                    .foregroundStyle(.primary.opacity(0.35))
                    .padding(.horizontal, style.horizontalPadding)
                    .padding(.vertical, style.verticalPadding)
                    .background(
                        RoundedRectangle(cornerRadius: style.cornerRadius)
                            .fill(Color.primary.opacity(0.06))
                    )
            }
        }
    }
}
