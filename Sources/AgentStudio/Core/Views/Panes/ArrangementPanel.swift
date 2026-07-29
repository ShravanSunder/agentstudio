import AgentStudioInfrastructure
import AgentStudioSharedComponents
import AppKit
import SwiftUI

private enum ArrangementPanelTooltipTarget: Hashable {
    case saveArrangement
}

/// Floating popover panel for managing pane arrangements.
/// Shows pane visibility toggles, arrangement chips, and save controls.
package struct ArrangementPanel: View {
    let tabId: UUID
    let workspaceWindowId: UUID?
    let octiconLoader: OcticonLoader
    let panes: [PaneVisibilityInfo]
    let zoomMode: ArrangementPanelZoomMode?
    let arrangements: [ArrangementInfo]
    @Bindable var inlineRenameState: ArrangementInlineRenameState
    let onPaneAction: (WorkspaceActionCommand) -> Void
    let onToggleZoom: (UUID?) -> Void
    let onSaveArrangement: () -> Void
    let onDismiss: () -> Void
    var highlightPaneId: UUID?

    @State private var highlightVisible = false
    @State private var hoveredArrangementId: UUID?
    @State private var isSaveButtonHovered = false
    @State private var tooltipFrames: [ArrangementPanelTooltipTarget: CGRect] = [:]
    @State private var focusedArrangementId: UUID?

    package init(
        tabId: UUID,
        workspaceWindowId: UUID?,
        octiconLoader: OcticonLoader,
        panes: [PaneVisibilityInfo],
        zoomMode: ArrangementPanelZoomMode?,
        arrangements: [ArrangementInfo],
        inlineRenameState: ArrangementInlineRenameState,
        onPaneAction: @escaping (WorkspaceActionCommand) -> Void,
        onToggleZoom: @escaping (UUID?) -> Void,
        onSaveArrangement: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        highlightPaneId: UUID? = nil
    ) {
        self.tabId = tabId
        self.workspaceWindowId = workspaceWindowId
        self.octiconLoader = octiconLoader
        self.panes = panes
        self.zoomMode = zoomMode
        self.arrangements = arrangements
        self.inlineRenameState = inlineRenameState
        self.onPaneAction = onPaneAction
        self.onToggleZoom = onToggleZoom
        self.onSaveArrangement = onSaveArrangement
        self.onDismiss = onDismiss
        self.highlightPaneId = highlightPaneId
    }

    private static let tooltipCoordinateSpaceName = "arrangementPanelTooltip"

    private var displayState: ArrangementPanelDisplayState {
        ArrangementPanelDisplayState(
            visiblePanes: panes,
            zoomMode: zoomMode,
            arrangements: arrangements
        )
    }

    private var transientSurfaceKind: TransientKeyboardSurfaceKind {
        if let editingArrangementId = inlineRenameState.editingArrangementId {
            return .arrangementRename(tabId: tabId, arrangementId: editingArrangementId)
        }
        return .arrangementPanel(tabId: tabId)
    }

    private var saveArrangementTooltip: ControlTooltipRenderValue {
        let actionSpec = LocalActionSpec.saveCurrentLayoutAsArrangement.actionSpec
        return actionSpec.controlTooltipRenderValue(
            provenance: .localAction(rawValue: actionSpec.label)
        )
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Arrangements")
                .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            ArrangementChipRow(spacing: 4) {
                ForEach(arrangements) { arrangement in
                    arrangementChip(arrangement)
                }

                if displayState.showsSaveArrangementButton {
                    Button(action: onSaveArrangement) {
                        Image(systemName: "plus")
                            .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                            .frame(width: 14, height: 14)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(
                        ArrangementChipButtonStyle(
                            isActive: false,
                            isHovered: isSaveButtonHovered,
                            minimumWidth: 30
                        )
                    )
                    .onHover { isSaveButtonHovered = $0 }
                    .hoverTooltipAnchor(
                        ArrangementPanelTooltipTarget.saveArrangement,
                        in: Self.tooltipCoordinateSpaceName
                    )
                    .controlHelp(saveArrangementTooltip)
                    .disabled(!displayState.allowsArrangementCreation)
                }
            }

            if let zoomMode {
                zoomModeSection(zoomMode)
            }

            if displayState.showsPaneVisibilitySection {
                Divider()
                    .padding(.vertical, 2)

                Text("Pane Visibility")
                    .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                VStack(spacing: 2) {
                    ForEach(panes) { pane in
                        paneRow(pane)
                    }
                }

            }
        }
        .padding(10)
        .frame(minWidth: 400, idealWidth: 475, maxWidth: 575)
        .overlay {
            GeometryReader { geometry in
                FloatingHoverTooltipPresenter(
                    activeTarget: isSaveButtonHovered ? .saveArrangement : nil,
                    anchorFrames: tooltipFrames,
                    availableWidth: geometry.size.width
                ) { target in
                    switch target {
                    case .saveArrangement:
                        saveArrangementTooltip
                    }
                }
            }
        }
        .coordinateSpace(name: Self.tooltipCoordinateSpaceName)
        .onPreferenceChange(HoverTooltipAnchorPreferenceKey<ArrangementPanelTooltipTarget>.self) {
            tooltipFrames = $0
        }
        .transientKeyboardSurface(
            transientSurfaceKind,
            workspaceWindowId: workspaceWindowId,
            onDismiss: onDismiss
        )
        .onAppear {
            guard highlightPaneId != nil else { return }
            highlightVisible = true
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                highlightVisible = false
            }
        }
        .onDisappear {
            if inlineRenameState.editingArrangementId != nil {
                inlineRenameState.cancel()
            }
        }
        .background(
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if inlineRenameState.editingArrangementId != nil {
                            cancelInlineRename()
                        }
                    }

            }
        )
    }

    private func zoomModeSection(_ zoomMode: ArrangementPanelZoomMode) -> some View {
        VStack(alignment: .leading, spacing: AppStyles.General.Spacing.standard) {
            Divider()
                .padding(.vertical, 2)

            Text("Pane Zoom")
                .font(.system(size: AppStyles.General.Typography.textSm, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            HStack(alignment: .center, spacing: AppStyles.General.Spacing.standard) {
                if let sourceIdentity = zoomMode.sourceIdentity {
                    VStack(alignment: .leading, spacing: AppStyles.General.Spacing.tight) {
                        Text(sourceIdentity.title)
                            .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let detail = sourceIdentity.detail {
                            Text(detail)
                                .font(.system(size: AppStyles.General.Typography.textXs))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(sourceIdentity.title)
                    .accessibilityValue(
                        sourceIdentity.fullPath
                            ?? sourceIdentity.detail
                            ?? sourceIdentity.title
                    )
                    .help(sourceIdentity.fullPath ?? sourceIdentity.title)
                }

                Spacer(minLength: 0)

                zoomModeButton(zoomMode)
            }
            .accessibilityElement(children: .contain)
            .background {
                AccessibilityLabelBridge(
                    identifier: "arrangement-panel-zoom-status",
                    label: "Pane Zoom"
                )
            }
        }
    }

    private func zoomModeButton(_ zoomMode: ArrangementPanelZoomMode) -> some View {
        Button {
            onToggleZoom(nil)
        } label: {
            HStack(spacing: AppStyles.General.Spacing.tight) {
                AppCommand.zoomPane.definition.icon.swiftUIImage(
                    loader: octiconLoader,
                    size: AppStyles.General.Typography.textSm
                )
                Text(zoomMode.label)
                    .font(.system(size: AppStyles.General.Typography.textXs, weight: .medium))
            }
            .padding(.horizontal, AppStyles.General.Spacing.standard)
            .frame(height: AppStyles.General.Button.compact)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.button)
                .fill(Color.white.opacity(AppStyles.General.Fill.active))
        )
        .controlHelp(AppCommand.zoomPane.definition.controlTooltipRenderValue())
        .accessibilityHidden(true)
        .background {
            AccessibilityPressBridge(
                identifier: "arrangement-panel-zoom-pane",
                label: zoomMode.label
            ) {
                onToggleZoom(nil)
            }
        }
    }

    private func paneRow(_ pane: PaneVisibilityInfo) -> some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            Group {
                if let statusSystemImageName = pane.statusSystemImageName {
                    Image(systemName: statusSystemImageName)
                        .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                        .foregroundStyle(.tertiary)
                } else {
                    Circle()
                        .fill(Color.white.opacity(AppStyles.General.Foreground.dim))
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                        .frame(width: 8, height: 8)
                }
            }
            .frame(
                width: AppStyles.General.Typography.textSm,
                height: AppStyles.General.Typography.textSm
            )

            Text(pane.title)
                .font(.system(size: AppStyles.General.Typography.textXs))
                .foregroundStyle(pane.isMinimized ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if pane.supportsZoom {
                Button {
                    onToggleZoom(pane.id)
                } label: {
                    AppCommand.zoomPane.definition.icon.swiftUIImage(
                        loader: octiconLoader,
                        size: AppStyles.General.Typography.textSm
                    )
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .controlHelp(AppCommand.zoomPane.definition.controlTooltipRenderValue())
                .accessibilityHidden(true)
                .background {
                    AccessibilityPressBridge(
                        identifier: "arrangement-panel-pane-\(pane.id.uuidString)-zoom",
                        label: AppCommand.zoomPane.definition.label
                    ) {
                        onToggleZoom(pane.id)
                    }
                }
            }

            Button {
                if pane.isMinimized {
                    onPaneAction(.expandPane(tabId: tabId, paneId: pane.id))
                } else {
                    onPaneAction(.minimizePane(tabId: tabId, paneId: pane.id))
                }
            } label: {
                Image(systemName: pane.isMinimized ? "eye" : "eye.slash")
                    .font(.system(size: AppStyles.General.Typography.textSm))
                    .foregroundStyle(.secondary)
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
            .background {
                AccessibilityPressBridge(
                    identifier: "arrangement-panel-pane-\(pane.id.uuidString)-visibility",
                    label: pane.isMinimized
                        ? LocalActionSpec.showPane.actionSpec.label
                        : LocalActionSpec.hidePane.actionSpec.label
                ) {
                    if pane.isMinimized {
                        onPaneAction(.expandPane(tabId: tabId, paneId: pane.id))
                    } else {
                        onPaneAction(.minimizePane(tabId: tabId, paneId: pane.id))
                    }
                }
            }
            .help(
                pane.isMinimized
                    ? LocalActionSpec.showPane.actionSpec.helpText
                    : LocalActionSpec.hidePane.actionSpec.helpText
            )
        }
        .padding(.horizontal, AppStyles.General.Spacing.standard)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.button)
                .fill(
                    pane.id == highlightPaneId && highlightVisible
                        ? Color.accentColor.opacity(AppStyles.General.Fill.selected)
                        : Color.white.opacity(AppStyles.General.Fill.subtle)
                )
        )
    }

    private func arrangementChip(_ arrangement: ArrangementInfo) -> some View {
        Group {
            if inlineRenameState.editingArrangementId == arrangement.id {
                ArrangementRenameTextField(
                    text: Binding(
                        get: { inlineRenameState.draftName },
                        set: { inlineRenameState.setDraftName($0) }
                    ),
                    isFocused: Binding(
                        get: { focusedArrangementId == arrangement.id },
                        set: { isFocused in
                            if isFocused {
                                focusedArrangementId = arrangement.id
                            } else if focusedArrangementId == arrangement.id {
                                focusedArrangementId = nil
                            }
                        }
                    ),
                    font: .systemFont(
                        ofSize: AppStyles.General.Typography.textXs,
                        weight: .semibold
                    ),
                    onCommit: commitInlineRename,
                    onCancel: cancelInlineRename
                )
                .foregroundStyle(.primary)
                .frame(minWidth: 72)
                .onAppear {
                    focusedArrangementId = arrangement.id
                }
            } else {
                arrangementChipBody(arrangement)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovering in
            hoveredArrangementId = isHovering ? arrangement.id : nil
        }
        .simultaneousGesture(doubleClickRenameGesture(arrangement))
        .contextMenu {
            if !arrangement.isDefault {
                Button(LocalActionSpec.renameArrangement.actionSpec.label) {
                    inlineRenameState.beginEditing(
                        arrangementId: arrangement.id,
                        currentName: arrangement.name,
                        isDefault: arrangement.isDefault
                    )
                }
                Button(LocalActionSpec.deleteArrangement.actionSpec.label, role: .destructive) {
                    onPaneAction(.removeArrangement(tabId: tabId, arrangementId: arrangement.id))
                }
            }
        }
    }

    private func arrangementChipBody(_ arrangement: ArrangementInfo) -> some View {
        let chipStyle = ArrangementChipVisualStyle(
            isActive: arrangement.isActive,
            isHovered: hoveredArrangementId == arrangement.id,
            isPressed: false
        )

        return HStack(spacing: 4) {
            Button {
                onPaneAction(.switchArrangement(tabId: tabId, arrangementId: arrangement.id))
            } label: {
                Text(arrangement.name)
                    .font(
                        .system(
                            size: AppStyles.General.Typography.textXs,
                            weight: arrangement.isActive ? .semibold : .regular
                        )
                    )
                    .foregroundStyle(chipStyle.foregroundIsPrimary ? .primary : .secondary)
            }
            .buttonStyle(.plain)

            if ArrangementChipAffordance.showsRenamePencil(role: arrangement.role) {
                Button {
                    inlineRenameState.beginEditing(
                        arrangementId: arrangement.id,
                        currentName: arrangement.name,
                        isDefault: arrangement.isDefault
                    )
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help(LocalActionSpec.renameArrangement.actionSpec.helpText)
            }
        }
        .padding(.horizontal, AppStyles.General.Spacing.loose)
        .padding(.vertical, AppStyles.General.Spacing.tight)
        .background(
            RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.bar)
                .fill(Color.white.opacity(chipStyle.backgroundOpacity))
        )
    }

    private func doubleClickRenameGesture(_ arrangement: ArrangementInfo) -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                inlineRenameState.beginEditing(
                    arrangementId: arrangement.id,
                    currentName: arrangement.name,
                    isDefault: arrangement.isDefault
                )
            }
    }

    private func commitInlineRename() {
        guard let payload = inlineRenameState.commit() else { return }
        focusedArrangementId = nil
        onPaneAction(.renameArrangement(tabId: tabId, arrangementId: payload.arrangementId, name: payload.name))
    }

    private func cancelInlineRename() {
        focusedArrangementId = nil
        inlineRenameState.cancel()
    }
}

struct ArrangementChipRow<Content: View>: View {
    let spacing: CGFloat
    let content: Content

    init(spacing: CGFloat = 4, @ViewBuilder content: () -> Content) {
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        HStack(spacing: spacing) {
            content
        }
    }
}

private struct ArrangementChipButtonStyle: ButtonStyle {
    let isActive: Bool
    let isHovered: Bool
    var minimumWidth: CGFloat?

    func makeBody(configuration: Configuration) -> some View {
        let chipStyle = ArrangementChipVisualStyle(
            isActive: isActive,
            isHovered: isHovered,
            isPressed: configuration.isPressed
        )

        return configuration.label
            .foregroundStyle(chipStyle.foregroundIsPrimary ? .primary : .secondary)
            .frame(minWidth: minimumWidth)
            .padding(.horizontal, AppStyles.General.Spacing.loose)
            .padding(.vertical, AppStyles.General.Spacing.tight)
            .background(
                RoundedRectangle(cornerRadius: AppStyles.General.CornerRadius.bar)
                    .fill(Color.white.opacity(chipStyle.backgroundOpacity))
            )
    }
}
