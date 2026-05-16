import SwiftUI

struct UnreadCountBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: AppStyles.Components.NotificationBadge.fontSize, weight: .bold))
            .foregroundStyle(.white)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, AppStyles.Components.NotificationBadge.horizontalPadding)
            .padding(.vertical, AppStyles.Components.NotificationBadge.verticalPadding)
            .background(
                Capsule()
                    .fill(Color.red)
            )
            .fixedSize()
    }
}
