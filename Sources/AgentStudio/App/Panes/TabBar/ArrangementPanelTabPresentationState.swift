import Foundation

struct ArrangementPanelTabPresentationState: Equatable {
    private(set) var presentedTabId: UUID?

    var isPresented: Bool {
        presentedTabId != nil
    }

    mutating func present(tabId: UUID) {
        presentedTabId = tabId
    }

    mutating func dismiss() {
        presentedTabId = nil
    }

    mutating func toggle(activeTabId: UUID?) {
        if isPresented {
            dismiss()
        } else if let activeTabId {
            present(tabId: activeTabId)
        }
    }

    mutating func setPresented(_ isPresented: Bool, activeTabId: UUID?) {
        if isPresented, let activeTabId {
            present(tabId: activeTabId)
        } else if !isPresented {
            dismiss()
        }
    }

    mutating func activeTabDidChange(to activeTabId: UUID?) {
        guard isPresented, presentedTabId != activeTabId else { return }
        dismiss()
    }
}
