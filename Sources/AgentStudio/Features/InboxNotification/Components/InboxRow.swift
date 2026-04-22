import SwiftUI

struct InboxRow: View {
    let notification: InboxNotification
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if !notification.isRead {
                    Circle()
                        .fill(.red)
                        .frame(width: 6, height: 6)
                }

                Text(notification.title)
                    .font(.system(size: 13, weight: notification.isRead ? .regular : .semibold))
                    .lineLimit(1)

                Spacer(minLength: 8)

                Text(relativeTime)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            if let contextLine {
                Text(contextLine)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let body = notification.body, !body.isEmpty {
                Text(body)
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

    private var contextLine: String? {
        if let repoName = notification.repoName {
            if let worktreeName = notification.worktreeName {
                if let branchName = notification.branchName, branchName != worktreeName {
                    return "\(repoName) · \(worktreeName) / \(branchName)"
                }
                return "\(repoName) · \(worktreeName)"
            }
            return repoName
        }

        if let branchName = notification.branchName {
            return branchName
        }

        return "unknown source"
    }
}
