import SwiftUI

// MARK: - CommandBarScopePill

/// Linear-style context indicator: "ParentLabel · ChildLabel ⊗"
/// Only shown when navigated into a nested level.
struct CommandBarScopePill: View {
    let parent: String?
    let child: String?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if let parent {
                Text(parent)
                    .foregroundStyle(.primary.opacity(0.60))
                Text(" · ")
                    .foregroundStyle(.primary.opacity(0.35))
            }
            if let child {
                Text(child)
                    .foregroundStyle(.primary.opacity(0.60))
            }

            Button(action: onDismiss) {
                Text(" ⊗")
                    .foregroundStyle(.primary.opacity(0.35))
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
        )
    }
}
