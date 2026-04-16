import SwiftUI

/// Floating popover panel for managing pane arrangements.
/// Shows pane visibility toggles, arrangement chips, and save controls.
struct ArrangementPanel: View {
    let tabId: UUID
    let panes: [PaneVisibilityInfo]
    let arrangements: [ArrangementInfo]
    let onPaneAction: (PaneActionCommand) -> Void
    let onSaveArrangement: () -> Void
    let showMinimizedBarsBinding: Binding<Bool>
    var highlightPaneId: UUID?
    var showsMinimizedBarToggle = true

    @State private var renamingArrangementId: UUID?
    @State private var renameText: String = ""
    @State private var highlightVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Arrangements")
                .font(.system(size: AppStyle.textSm, weight: .semibold))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)

            WrappingHStack(spacing: 4) {
                ForEach(arrangements) { arrangement in
                    arrangementChip(arrangement)
                }

                if panes.count > 1 {
                    Button(action: onSaveArrangement) {
                        Image(systemName: "plus")
                            .font(.system(size: AppStyle.textSm, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .strokeBorder(Color.white.opacity(AppStyle.strokeMuted), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(LocalActionSpec.saveCurrentLayoutAsArrangement.actionSpec.helpText)
                }
            }

            if panes.count > 1 {
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

                if showsMinimizedBarToggle {
                    Divider()
                        .padding(.vertical, 2)

                    HStack {
                        Text("Show minimized panes")
                            .font(.system(size: AppStyle.textXs))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Toggle(
                            "",
                            isOn: showMinimizedBarsBinding
                        )
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                        .labelsHidden()
                    }

                    if !showMinimizedBarsBinding.wrappedValue && atom(\.managementMode).isActive {
                        Text("Minimized panes are always shown in management mode")
                            .font(.system(size: AppStyle.textXs))
                            .foregroundStyle(.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 240, maxWidth: 340)
        .alert(
            "Rename Arrangement",
            isPresented: Binding(
                get: { renamingArrangementId != nil },
                set: { if !$0 { renamingArrangementId = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button(LocalActionSpec.rename.actionSpec.label) {
                if let arrangementId = renamingArrangementId, !renameText.isEmpty {
                    onPaneAction(.renameArrangement(tabId: tabId, arrangementId: arrangementId, name: renameText))
                }
                renamingArrangementId = nil
            }
            Button(LocalActionSpec.cancel.actionSpec.label, role: .cancel) {
                renamingArrangementId = nil
            }
        }
        .onAppear {
            guard highlightPaneId != nil else { return }
            highlightVisible = true
            withAnimation(.easeOut(duration: 0.6).delay(0.3)) {
                highlightVisible = false
            }
        }
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
        Text(arrangement.name)
            .font(.system(size: AppStyle.textXs, weight: arrangement.isActive ? .semibold : .regular))
            .foregroundStyle(arrangement.isActive ? .primary : .secondary)
            .padding(.horizontal, AppStyle.spacingLoose)
            .padding(.vertical, AppStyle.spacingTight)
            .background(
                RoundedRectangle(cornerRadius: AppStyle.barCornerRadius)
                    .fill(
                        arrangement.isActive
                            ? Color.white.opacity(AppStyle.fillActive) : Color.white.opacity(AppStyle.fillSubtle)
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onPaneAction(.switchArrangement(tabId: tabId, arrangementId: arrangement.id))
            }
            .contextMenu {
                if !arrangement.isDefault {
                    Button(LocalActionSpec.renameArrangement.actionSpec.label) {
                        renameText = arrangement.name
                        renamingArrangementId = arrangement.id
                    }
                    Button(LocalActionSpec.deleteArrangement.actionSpec.label, role: .destructive) {
                        onPaneAction(.removeArrangement(tabId: tabId, arrangementId: arrangement.id))
                    }
                }
            }
    }
}

struct WrappingHStack<Content: View>: View {
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
