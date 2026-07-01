import SwiftUI

struct TabBarArrangementChip: View {
    let index: Int?
    let name: String?
    let isHovered: Bool
    let isPressed: Bool
    let nameMaxWidth: CGFloat

    var styleContract: ChromeToolbarCapsuleStyleContract {
        ChromeToolbarCapsuleStyleContract(isHovered: isHovered, isPressed: isPressed)
    }

    var hasCustomArrangement: Bool {
        index != nil && name != nil
    }

    var showsArrangementName: Bool {
        name != nil
    }

    private var contentForegroundColor: Color {
        ChromeToolbarControlPalette.foregroundColor(isSelected: false, isHovered: isHovered)
    }

    static func nameMaxWidth(isManagementLayerActive: Bool) -> CGFloat {
        isManagementLayerActive ? 200 : 100
    }

    var body: some View {
        let styleContract = styleContract

        HStack(spacing: 6) {
            Image(systemName: "rectangle.3.group")
                .font(.system(size: styleContract.iconSize, weight: .medium))
                .foregroundStyle(contentForegroundColor)

            if let name {
                HStack(spacing: 4) {
                    if let index {
                        Text("\(index)")
                            .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                            .foregroundStyle(contentForegroundColor)
                        Text("·")
                            .font(.system(size: AppStyles.General.Typography.textXs))
                            .foregroundStyle(contentForegroundColor)
                    }
                    Text(name)
                        .font(.system(size: AppStyles.General.Typography.textXs))
                        .foregroundStyle(contentForegroundColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: nameMaxWidth)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(height: styleContract.height)
        .padding(.horizontal, showsArrangementName ? 8 : 0)
        .frame(minWidth: styleContract.minimumWidth)
        .background(
            ChromeToolbarCapsuleBackground(
                isHovered: styleContract.isHovered,
                isPressed: styleContract.isPressed
            )
        )
        .contentShape(Capsule())
        .animation(.easeInOut(duration: AppStyles.General.Animation.standard), value: showsArrangementName)
        .animation(.easeInOut(duration: AppStyles.General.Animation.standard), value: name)
    }
}

struct ChromeToolbarCapsuleStyleContract: Equatable {
    let height = AppStyles.Shell.Chrome.ToolbarButton.size
    let minimumWidth = AppStyles.Shell.Chrome.ToolbarButton.size
    let iconSize = AppStyles.Shell.Chrome.ToolbarButton.iconSize
    let isHovered: Bool
    let isPressed: Bool
    let usesToolbarBackground = true
}
