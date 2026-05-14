import SwiftUI

struct InboxRow: View {
    let notification: InboxNotification
    let now: Date
    let rowContext: InboxNotificationSourceDisplay.RowContext

    static var leadingIndicatorColumnWidth: CGFloat {
        AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth
    }

    static func metadataLine(
        iconSystemName: String? = nil,
        text: String,
        prominence: SidebarMetadataProminence = .secondary
    ) -> SidebarMetadataLine {
        SidebarMetadataLine(iconSystemName: iconSystemName, text: text, prominence: prominence)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
            HStack(spacing: AppStyles.General.Spacing.tight) {
                unreadIndicator
                    .frame(width: Self.leadingIndicatorColumnWidth, alignment: .leading)

                Text(display.primaryText)
                    .font(
                        .system(
                            size: AppStyles.Shell.Sidebar.notificationRowTitleSize,
                            weight: notification.isRead ? .regular : .semibold
                        )
                    )
                    .foregroundStyle(notification.isRead ? .secondary : .primary)
                    .lineLimit(1)
                    .layoutPriority(1)

                Spacer(minLength: AppStyles.General.Spacing.standard)

                Text(relativeTime)
                    .font(
                        .system(
                            size: AppStyles.Shell.Sidebar.notificationRowTimestampSize,
                            weight: .semibold
                        )
                    )
                    .foregroundStyle(.secondary)
            }

            Self.metadataLine(text: display.sourceLine)

            if let placementLine = display.placementLine {
                Self.metadataLine(
                    iconSystemName: "terminal",
                    text: placementLine,
                    prominence: .secondary
                )
            }

            if let detailText = display.detailText {
                Self.metadataLine(text: detailText, prominence: .tertiary)
            }
        }
    }

    @ViewBuilder
    private var unreadIndicator: some View {
        if notification.isRead {
            Color.clear
        } else {
            Circle()
                .fill(.red)
                .frame(
                    width: AppStyles.Shell.Sidebar.notificationRowUnreadDotSize,
                    height: AppStyles.Shell.Sidebar.notificationRowUnreadDotSize
                )
        }
    }

    private var display: InboxNotificationSourceDisplay {
        InboxNotificationSourceDisplay(notification: notification, rowContext: rowContext)
    }

    private var relativeTime: String {
        let delta = max(0, now.timeIntervalSince(notification.timestamp))
        if delta < 60 {
            return "now"
        }
        if delta < 3600 {
            return "\(Int(delta / 60))m"
        }
        if delta < 86_400 {
            return "\(Int(delta / 3600))h"
        }
        return "\(Int(delta / 86_400))d"
    }
}
