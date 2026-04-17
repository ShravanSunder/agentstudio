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
        if isPressed { return AppStyle.fillActive }
        if isHovered { return AppStyle.fillPressed }
        return AppStyle.fillMuted
    }

    static func nameMaxWidth(isManagementLayerActive: Bool) -> CGFloat {
        isManagementLayerActive ? 200 : 100
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: AppStyle.compactIconSize, weight: .medium))
                .foregroundStyle(isHovered ? .primary : .secondary)

            if let index, let name {
                HStack(spacing: 4) {
                    Text("\(index)")
                        .font(.system(size: AppStyle.textXs, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("·")
                        .font(.system(size: AppStyle.textXs))
                        .foregroundStyle(.tertiary)
                    Text(name)
                        .font(.system(size: AppStyle.textXs))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: nameMaxWidth)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: AppStyle.toolbarButtonSize)
        .padding(.horizontal, hasCustomArrangement ? 8 : 0)
        .frame(minWidth: AppStyle.toolbarButtonSize)
        .background(
            Capsule()
                .fill(Color.white.opacity(chipFillOpacity))
        )
        .contentShape(Capsule())
        .animation(.easeInOut(duration: AppStyle.animationStandard), value: hasCustomArrangement)
        .animation(.easeInOut(duration: AppStyle.animationStandard), value: name)
    }
}
