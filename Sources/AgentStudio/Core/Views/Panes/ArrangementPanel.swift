import AppKit
import SwiftUI

/// Floating popover panel for managing pane arrangements.
/// Shows pane visibility toggles, arrangement chips, and save controls.
struct ArrangementPanel: View {
    let tabId: UUID
    let workspaceWindowId: UUID?
    let panes: [PaneVisibilityInfo]
    let arrangements: [ArrangementInfo]
    @Bindable var inlineRenameState: ArrangementInlineRenameState
    let onPaneAction: (PaneActionCommand) -> Void
    let onSaveArrangement: () -> Void
    let showsMinimizedPanesBinding: Binding<Bool>
    var highlightPaneId: UUID?
    var showsMinimizedBarToggle = true

    @State private var highlightVisible = false
    @State private var hoveredArrangementId: UUID?
    @State private var isSaveButtonHovered = false
    @State private var hasClaimedFocus = false
    @State private var focusedArrangementId: UUID?

    private var displayState: ArrangementPanelDisplayState {
        ArrangementPanelDisplayState(
            visiblePanes: panes,
            arrangements: arrangements,
            allowsMinimizedBarToggle: showsMinimizedBarToggle
        )
    }

    private var transientSurfaceKind: TransientKeyboardSurfaceKind {
        if let editingArrangementId = inlineRenameState.editingArrangementId {
            return .arrangementRename(tabId: tabId, arrangementId: editingArrangementId)
        }
        return .arrangementPanel(tabId: tabId)
    }

    var body: some View {
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
                    .help(LocalActionSpec.saveCurrentLayoutAsArrangement.actionSpec.helpText)
                }
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

                if displayState.showsMinimizedBarToggle {
                    HStack(spacing: 6) {
                        Text("Show minimized panes")
                            .font(.system(size: AppStyles.General.Typography.textXs))
                            .foregroundStyle(.secondary)

                        let minimizedCount = panes.filter(\.isMinimized).count
                        if minimizedCount > 0 {
                            Text("\(minimizedCount)")
                                .font(.system(size: AppStyles.General.Typography.textXs, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, AppStyles.General.Spacing.tight)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(AppStyles.General.Fill.hover))
                                )
                                .fixedSize()
                        }

                        Spacer()

                        Toggle(
                            "",
                            isOn: showsMinimizedPanesBinding
                        )
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                        .disabled(atom(\.managementLayer).isActive)
                    }
                    .padding(.top, AppStyles.General.Spacing.standard)

                    if !showsMinimizedPanesBinding.wrappedValue && atom(\.managementLayer).isActive {
                        Text("Minimized panes are always shown in management mode")
                            .font(.system(size: AppStyles.General.Typography.textXs))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 400, idealWidth: 475, maxWidth: 575)
        .transientKeyboardSurface(transientSurfaceKind, workspaceWindowId: workspaceWindowId)
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
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture {
                    if inlineRenameState.editingArrangementId != nil {
                        cancelInlineRename()
                    }
                }
        )
    }

    private func paneRow(_ pane: PaneVisibilityInfo) -> some View {
        HStack(spacing: AppStyles.General.Spacing.standard) {
            Circle()
                .fill(pane.isMinimized ? Color.clear : Color.white.opacity(AppStyles.General.Foreground.dim))
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: 8, height: 8)

            Text(pane.title)
                .font(.system(size: AppStyles.General.Typography.textXs))
                .foregroundStyle(pane.isMinimized ? .tertiary : .primary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

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
                                hasClaimedFocus = true
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
                    hasClaimedFocus = true
                }
                .onDisappear {
                    hasClaimedFocus = false
                }
                .onChange(of: focusedArrangementId) { _, newValue in
                    guard hasClaimedFocus,
                        newValue != arrangement.id,
                        inlineRenameState.editingArrangementId == arrangement.id
                    else { return }
                    cancelInlineRename()
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

            if ArrangementChipAffordance.showsRenamePencil(isDefault: arrangement.isDefault) {
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
