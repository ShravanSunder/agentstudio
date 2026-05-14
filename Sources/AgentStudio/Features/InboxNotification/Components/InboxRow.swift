import SwiftUI

struct InboxRow: View {
    let notification: InboxNotification
    let now: Date
    let rowContext: InboxNotificationSourceDisplay.RowContext

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
            HStack(spacing: AppStyles.General.Spacing.standard) {
                if !notification.isRead {
                    Circle()
                        .fill(.red)
                        .frame(
                            width: AppStyles.Shell.Sidebar.notificationRowUnreadDotSize,
                            height: AppStyles.Shell.Sidebar.notificationRowUnreadDotSize
                        )
                }

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

            Text(display.sourceLine)
                .font(.system(size: AppStyles.Shell.Sidebar.notificationRowSourceSize, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let placementLine = display.placementLine {
                Text(placementLine)
                    .font(.system(size: AppStyles.Shell.Sidebar.notificationRowDetailSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let detailText = display.detailText {
                Text(detailText)
                    .font(.system(size: AppStyles.Shell.Sidebar.notificationRowDetailSize))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
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
