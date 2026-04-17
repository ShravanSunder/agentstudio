import AppKit
import SwiftUI

/// Floating popover panel for managing pane arrangements.
/// Shows pane visibility toggles, arrangement chips, and save controls.
struct ArrangementPanel: View {
    let tabId: UUID
    let panes: [PaneVisibilityInfo]
    let arrangements: [ArrangementInfo]
    @Bindable var inlineRenameState: ArrangementInlineRenameState
    let onPaneAction: (PaneActionCommand) -> Void
    let onSaveArrangement: () -> Void
    let showMinimizedBarsBinding: Binding<Bool>
    var highlightPaneId: UUID?
    var showsMinimizedBarToggle = true

    @State private var highlightVisible = false
    @State private var hoveredArrangementId: UUID?
    @State private var isSaveButtonHovered = false
    @State private var hasClaimedFocus = false
    @FocusState private var focusedArrangementId: UUID?

    private var displayState: ArrangementPanelDisplayState {
        ArrangementPanelDisplayState(
            visiblePanes: panes,
            arrangements: arrangements,
            allowsMinimizedBarToggle: showsMinimizedBarToggle
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Arrangements")
                .font(.system(size: AppStyle.textSm, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            ArrangementChipRow(spacing: 4) {
                ForEach(arrangements) { arrangement in
                    arrangementChip(arrangement)
                }

                if displayState.showsSaveArrangementButton {
                    Button(action: onSaveArrangement) {
                        Image(systemName: "plus")
                            .font(.system(size: AppStyle.textXs, weight: .semibold))
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
                    .font(.system(size: AppStyle.textSm, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)

                VStack(spacing: 2) {
                    ForEach(panes) { pane in
                        paneRow(pane)
                    }
                }

                if displayState.showsMinimizedBarToggle {
                    Divider()
                        .padding(.vertical, 2)

                    HStack(spacing: 6) {
                        Text("Show minimized panes")
                            .font(.system(size: AppStyle.textXs))
                            .foregroundStyle(.secondary)

                        let minimizedCount = panes.filter(\.isMinimized).count
                        if minimizedCount > 0 {
                            Text("\(minimizedCount)")
                                .font(.system(size: AppStyle.textXs, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, AppStyle.spacingTight)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(Color.white.opacity(AppStyle.fillHover))
                                )
                                .fixedSize()
                        }

                        Spacer()

                        Toggle(
                            "",
                            isOn: showMinimizedBarsBinding
                        )
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if !showMinimizedBarsBinding.wrappedValue && atom(\.managementLayer).isActive {
                        Text("Minimized panes are always shown in management mode")
                            .font(.system(size: AppStyle.textXs))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 400, idealWidth: 475, maxWidth: 575)
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
        HStack(spacing: AppStyle.spacingStandard) {
            Circle()
                .fill(pane.isMinimized ? Color.clear : Color.white.opacity(AppStyle.foregroundDim))
                .stroke(Color.white.opacity(0.3), lineWidth: 1)
                .frame(width: 8, height: 8)

            Text(pane.title)
                .font(.system(size: AppStyle.textXs))
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
                    .font(.system(size: AppStyle.textSm))
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
        .padding(.horizontal, AppStyle.spacingStandard)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.buttonCornerRadius)
                .fill(
                    pane.id == highlightPaneId && highlightVisible
                        ? Color.accentColor.opacity(0.15)
                        : Color.white.opacity(AppStyle.fillSubtle)
                )
        )
    }

    private func arrangementChip(_ arrangement: ArrangementInfo) -> some View {
        Group {
            if inlineRenameState.editingArrangementId == arrangement.id {
                TextField(
                    "Arrangement name",
                    text: Binding(
                        get: { inlineRenameState.draftName },
                        set: { inlineRenameState.setDraftName($0) }
                    )
                )
                .textFieldStyle(.plain)
                .font(.system(size: AppStyle.textXs, weight: .semibold))
                .foregroundStyle(.primary)
                .focused($focusedArrangementId, equals: arrangement.id)
                .frame(minWidth: 72)
                .onSubmit(commitInlineRename)
                .onExitCommand(perform: cancelInlineRename)
                .onAppear {
                    Task { @MainActor in
                        focusedArrangementId = arrangement.id
                        hasClaimedFocus = true
                        if let editor = NSApp.keyWindow?.firstResponder as? NSTextView {
                            editor.selectAll(nil)
                        }
                    }
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
                    .font(.system(size: AppStyle.textXs, weight: arrangement.isActive ? .semibold : .regular))
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
        .padding(.horizontal, AppStyle.spacingLoose)
        .padding(.vertical, AppStyle.spacingTight)
        .background(
            RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
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
            .padding(.horizontal, AppStyle.spacingLoose)
            .padding(.vertical, AppStyle.spacingTight)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                    .fill(Color.white.opacity(chipStyle.backgroundOpacity))
            )
    }
}
