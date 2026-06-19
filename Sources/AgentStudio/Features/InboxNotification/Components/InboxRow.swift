import SwiftUI

struct InboxRow: View {
    let notification: InboxNotification
    let now: Date
    let rowContext: InboxNotificationSourceDisplay.RowContext
    var grouping: InboxNotificationGrouping = .none

    static let placementMetadataIconSystemName: String? = nil

    static func metadataLine(
        iconSystemName: String? = nil,
        text: String,
        prominence: SidebarMetadataProminence = .secondary
    ) -> SidebarMetadataLine {
        SidebarMetadataLine(
            iconSystemName: iconSystemName,
            reservesIconColumn: false,
            text: text,
            prominence: prominence
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppStyles.Shell.Sidebar.rowContentSpacing) {
            HStack(spacing: AppStyles.General.Spacing.tight) {
                Text(display.primaryText)
                    .font(
                        .system(
                            size: AppStyles.Shell.Sidebar.notificationRowTitleSize,
                            weight: notification.isRead ? .regular : .semibold
                        )
                    )
                    .foregroundStyle(notification.isRead ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(0)

                Spacer(minLength: AppStyles.General.Spacing.standard)

                timestampCluster
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(2)
            }

            Self.metadataLine(text: display.sourceLine)

            if let placementLine = display.placementLine {
                Self.metadataLine(
                    iconSystemName: Self.placementMetadataIconSystemName,
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
    private var timestampCluster: some View {
        HStack(spacing: AppStyles.General.Spacing.tight) {
            if !notification.isRead {
                Circle()
                    .fill(laneDotColor)
                    .frame(
                        width: AppStyles.Shell.Sidebar.notificationRowUnreadDotSize,
                        height: AppStyles.Shell.Sidebar.notificationRowUnreadDotSize
                    )
                    .accessibilityLabel(laneAccessibilityLabel)
            }

            Text(relativeTime)
                .font(
                    .system(
                        size: AppStyles.Shell.Sidebar.notificationRowTimestampSize,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.secondary)
        }
    }

    private var display: InboxNotificationSourceDisplay {
        InboxNotificationSourceDisplay(notification: notification, rowContext: rowContext, grouping: grouping)
    }

    private var laneDotColor: Color {
        switch notification.displayLane {
        case .actionNeeded:
            return .red
        case .safety:
            return .orange
        case .settledAgent:
            return .yellow
        case .activity:
            return .blue
        }
    }

    private var laneAccessibilityLabel: String {
        switch notification.displayLane {
        case .actionNeeded:
            return "Action needed unread"
        case .safety:
            return "Safety unread"
        case .settledAgent:
            return "Agent settled unread"
        case .activity:
            return "Activity unread"
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
