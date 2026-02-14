import SwiftUI

/// View-layer data model for a single arrangement chip in the bar.
struct ArrangementBarItem: Identifiable {
    let id: UUID
    let name: String
    let isDefault: Bool
    let paneCount: Int
}

/// Floating arrangement bar that appears below the tab bar.
/// Shows arrangement chips for quick switching between named pane arrangements.
/// Hosted in an `NSHostingView` overlay within `MainSplitViewController`.
struct ArrangementBar: View {
    let arrangements: [ArrangementBarItem]
    let activeArrangementId: UUID?
    let onSwitch: (UUID) -> Void
    let onSaveNew: () -> Void
    let onDelete: (UUID) -> Void
    let onRename: (UUID) -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(arrangements) { arrangement in
                ArrangementChip(
                    name: arrangement.name,
                    isActive: arrangement.id == activeArrangementId,
                    isDefault: arrangement.isDefault,
                    onSelect: { onSwitch(arrangement.id) },
                    onDelete: arrangement.isDefault ? nil : { onDelete(arrangement.id) },
                    onRename: { onRename(arrangement.id) }
                )
            }

            Button(action: onSaveNew) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(4)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
        )
        .padding(.horizontal, 8)
    }
}

/// Individual pill-shaped chip representing a single arrangement.
/// Active state uses a subtle highlight; right-click exposes rename/delete.
struct ArrangementChip: View {
    let name: String
    let isActive: Bool
    let isDefault: Bool
    let onSelect: () -> Void
    let onDelete: (() -> Void)?
    let onRename: () -> Void

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: isActive ? .semibold : .regular))
            .foregroundStyle(isActive ? .primary : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isActive ? Color.white.opacity(0.12) : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture(perform: onSelect)
            .contextMenu {
                Button("Rename...") { onRename() }
                if let onDelete {
                    Button("Delete", role: .destructive) { onDelete() }
                }
            }
    }
}

// MARK: - Preview

#if DEBUG
struct ArrangementBar_Previews: PreviewProvider {
    static var previews: some View {
        let items: [ArrangementBarItem] = [
            ArrangementBarItem(id: UUID(), name: "Default", isDefault: true, paneCount: 3),
            ArrangementBarItem(id: UUID(), name: "Focus", isDefault: false, paneCount: 1),
            ArrangementBarItem(id: UUID(), name: "Debug", isDefault: false, paneCount: 2),
        ]
        let activeId = items[0].id

        return VStack {
            Spacer()
            ArrangementBar(
                arrangements: items,
                activeArrangementId: activeId,
                onSwitch: { _ in },
                onSaveNew: {},
                onDelete: { _ in },
                onRename: { _ in },
                onDismiss: {}
            )
            Spacer()
        }
        .frame(width: 500, height: 200)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
#endif
