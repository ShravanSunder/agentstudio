import AgentStudioInfrastructure
import AppKit
import Observation
import SwiftUI

struct RepoExplorerTableRowReuseToken: Hashable {
    let rawValue: UInt64
}

struct RepoExplorerTableRowBindingIdentity: Equatable {
    let visibleGeneration: UInt64
    let rowID: RepoExplorerRowID
    let reuseToken: RepoExplorerTableRowReuseToken
}

struct RepoExplorerTableRowBinding: Equatable {
    let identity: RepoExplorerTableRowBindingIdentity
    let row: RepoExplorerMaterializedRow
}

@MainActor
@Observable
final class RepoExplorerTableRowSlot {
    private(set) var binding: RepoExplorerTableRowBinding?

    func install(_ binding: RepoExplorerTableRowBinding) {
        self.binding = binding
    }

    func clear() {
        binding = nil
    }
}

struct RepoExplorerTableRowHostingRoot: View {
    @Bindable var slot: RepoExplorerTableRowSlot
    let octiconLoader: OcticonLoader

    var body: some View {
        Group {
            if let binding = slot.binding {
                RepoExplorerMaterializedRowView(
                    row: binding.row,
                    octiconLoader: octiconLoader
                )
                .id(binding.identity.rowID)
            }
        }
    }
}

@MainActor
final class RepoExplorerTableRowCell: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("repo-explorer-hosted-row")

    let hostingView: NSHostingView<RepoExplorerTableRowHostingRoot>
    private let slot = RepoExplorerTableRowSlot()
    private var reuseSequence: UInt64 = 0

    var currentBindingIdentity: RepoExplorerTableRowBindingIdentity? {
        slot.binding?.identity
    }

    init(octiconLoader: OcticonLoader) {
        hostingView = NSHostingView(
            rootView: RepoExplorerTableRowHostingRoot(
                slot: slot,
                octiconLoader: octiconLoader
            )
        )
        super.init(frame: .zero)

        identifier = Self.reuseIdentifier
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.row)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    @discardableResult
    func bind(
        row: RepoExplorerMaterializedRow,
        visibleGeneration: UInt64
    ) -> RepoExplorerTableRowBindingIdentity {
        if let currentBinding = slot.binding,
            currentBinding.identity.visibleGeneration == visibleGeneration,
            currentBinding.row == row
        {
            return currentBinding.identity
        }
        clearBindingForReuse()
        reuseSequence &+= 1
        let identity = RepoExplorerTableRowBindingIdentity(
            visibleGeneration: visibleGeneration,
            rowID: row.id,
            reuseToken: RepoExplorerTableRowReuseToken(rawValue: reuseSequence)
        )
        slot.install(RepoExplorerTableRowBinding(identity: identity, row: row))
        setAccessibilityLabel(RepoExplorerMaterializedRowView.accessibilityLabel(for: row))
        return identity
    }

    func clearBindingForReuse() {
        slot.clear()
        setAccessibilityLabel(nil)
    }

    @discardableResult
    func performIfCurrent(
        _ identity: RepoExplorerTableRowBindingIdentity,
        operation: () -> Void
    ) -> Bool {
        guard currentBindingIdentity == identity else { return false }
        operation()
        return true
    }
}
