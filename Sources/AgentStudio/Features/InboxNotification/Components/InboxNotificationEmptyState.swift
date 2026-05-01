import SwiftUI

struct InboxNotificationEmptyState: View {
    var body: some View {
        VStack {
            Text("No notifications yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
