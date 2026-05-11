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
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if !notification.isRead {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                }

                Text(display.primaryText)
                    .font(.system(size: 13, weight: notification.isRead ? .regular : .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(relativeTime)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Text(display.sourceLine)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let placementLine = display.placementLine {
                Text(placementLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let detailText = display.detailText {
                Text(detailText)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
