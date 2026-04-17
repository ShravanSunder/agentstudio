import SwiftUI

struct TabBarArrangementChip: View {
    let index: Int?
    let name: String?
    let isHovered: Bool
    let isPressed: Bool
    let nameMaxWidth: CGFloat

    var hasCustomArrangement: Bool {
        index != nil && name != nil
    }

    var chipFillOpacity: CGFloat {
        if isPressed { return AppStyles.General.Fill.active }
        if isHovered { return AppStyles.General.Fill.pressed }
        return AppStyles.General.Fill.muted
    }

    static func nameMaxWidth(isManagementLayerActive: Bool) -> CGFloat {
        isManagementLayerActive ? 200 : 100
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: AppStyles.General.Icon.compact, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)

            if let index, let name {
                HStack(spacing: 4) {
                    Text("\(index)")
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: AppStyles.General.Typography.textXs))
                        .foregroundStyle(.tertiary)
                    Text(name)
                        .font(.system(size: AppStyles.General.Typography.textXs))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: nameMaxWidth)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: AppStyles.General.Button.toolbar)
        .padding(.horizontal, hasCustomArrangement ? 8 : 0)
        .frame(minWidth: AppStyles.General.Button.toolbar)
        .background(
            Capsule()
                .fill(Color.white.opacity(chipFillOpacity))
        )
        .contentShape(Capsule())
        .animation(.easeInOut(duration: AppStyles.General.Animation.standard), value: hasCustomArrangement)
        .animation(.easeInOut(duration: AppStyles.General.Animation.standard), value: name)
    }
}
