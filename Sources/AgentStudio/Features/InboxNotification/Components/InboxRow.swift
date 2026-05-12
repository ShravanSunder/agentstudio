import SwiftUI

struct InboxRow: View {
    let notification: InboxNotification
    let now: Date
    let rowContext: InboxNotificationSourceDisplay.RowContext

    private var display: InboxNotificationSourceDisplay {
        InboxNotificationSourceDisplay(notification: notification, rowContext: rowContext)
    }

    init(
        notification: InboxNotification,
        now: Date,
        rowContext: InboxNotificationSourceDisplay.RowContext = .globalInbox
    ) {
        self.notification = notification
        self.now = now
        self.rowContext = rowContext
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
            HStack(spacing: AppStyles.General.Spacing.tight) {
                unreadDot
                    .frame(width: AppStyles.Shell.Sidebar.rowLeadingIconColumnWidth, alignment: .leading)

                Text(display.primaryText)
                    .font(
                        .system(
                            size: AppStyles.General.Typography.textBase,
                            weight: notification.isRead ? .regular : .semibold)
                    )
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(relativeTime)
                    .font(.system(size: AppStyles.Shell.Sidebar.branchFontSize, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            SidebarMetadataLine(
                text: display.sourceLine,
                prominence: .secondary
            )

            if let placementLine = display.placementLine {
                SidebarMetadataLine(
                    iconSystemName: "terminal",
                    text: placementLine,
                    prominence: .secondary
                )
            }

            if let detailText = display.detailText {
                SidebarMetadataLine(
                    text: detailText,
                    prominence: .tertiary
                )
            }
        }
    }

    @ViewBuilder
    private var unreadDot: some View {
        if notification.isRead {
            Color.clear
                .frame(width: 6, height: 6)
        } else {
            Circle()
                .fill(.red)
                .frame(width: 6, height: 6)
        }
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
