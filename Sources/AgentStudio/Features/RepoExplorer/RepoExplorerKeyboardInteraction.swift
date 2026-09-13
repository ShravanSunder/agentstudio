import AgentStudioCore
import AppKit
import Observation

@MainActor
struct RepoExplorerKeyboardCallbacks {
    var canInterpretListInput: () -> Bool = { false }
    var onFilterFocusRequest: () -> Void = {}
    var onReturnFocusRequest: () -> Void = {}
    var onSidebarFocusChange: (Bool) -> Void = { _ in }
    var onCommandRequest: (AppCommand) -> Void = { _ in }
}

/// Reports native list and SwiftUI field focus without owning workspace keyboard routing.
@MainActor
@Observable
final class RepoExplorerKeyboardInteraction {
    enum FocusedRegion: Equatable {
        case unfocused
        case list
        case filter
    }

    private(set) var focusedRegion: FocusedRegion = .unfocused
    @ObservationIgnored private weak var listHost: RepoExplorerMaterializationHost?
    @ObservationIgnored private var callbacks = RepoExplorerKeyboardCallbacks()
    @ObservationIgnored private var hasPendingFilterFocusRequest = false

    var isListKeyboardActive: Bool {
        focusedRegion == .list && listIsFirstResponder && callbacks.canInterpretListInput()
    }

    private var listIsFirstResponder: Bool {
        guard let listHost, let window = listHost.window else { return false }
        return window.firstResponder === listHost
    }

    func configure(_ callbacks: RepoExplorerKeyboardCallbacks) {
        self.callbacks = callbacks
    }

    func attach(_ host: RepoExplorerMaterializationHost) {
        guard listHost !== host else { return }
        clearFocusReporting()
        listHost = host
    }

    func detach(_ host: RepoExplorerMaterializationHost) {
        guard listHost === host else { return }
        clearFocusReporting()
        listHost = nil
    }

    func listDidBecomeFirstResponder(_ host: RepoExplorerMaterializationHost) {
        guard listHost === host else { return }
        hasPendingFilterFocusRequest = false
        setFocusedRegion(.list)
    }

    func listDidResignFirstResponder(_ host: RepoExplorerMaterializationHost) {
        guard listHost === host, focusedRegion == .list else { return }
        setFocusedRegion(.unfocused)
    }

    func filterFocusDidChange(isFocused: Bool) {
        if isFocused {
            // A delayed field callback must not undo a newer native list-focus request.
            guard hasPendingFilterFocusRequest || !listIsFirstResponder else { return }
            hasPendingFilterFocusRequest = false
            setFocusedRegion(.filter)
        } else {
            hasPendingFilterFocusRequest = false
            if listIsFirstResponder {
                setFocusedRegion(.list)
            } else if focusedRegion == .filter {
                setFocusedRegion(.unfocused)
            }
        }
    }

    func requestFilterFocus() {
        hasPendingFilterFocusRequest = true
        callbacks.onFilterFocusRequest()
    }

    @discardableResult
    func requestListFocus() -> Bool {
        guard let listHost, let window = listHost.window,
            !listHost.isHiddenOrHasHiddenAncestor
        else { return false }
        hasPendingFilterFocusRequest = false
        guard window.makeFirstResponder(listHost), window.firstResponder === listHost else { return false }
        // AppKit can skip becomeFirstResponder when this responder already owns focus.
        listDidBecomeFirstResponder(listHost)
        return true
    }

    func returnFromList() {
        hasPendingFilterFocusRequest = false
        callbacks.onReturnFocusRequest()
    }

    func requestCommand(_ command: AppCommand) {
        callbacks.onCommandRequest(command)
    }

    func clearFocusReporting() {
        hasPendingFilterFocusRequest = false
        setFocusedRegion(.unfocused)
    }

    private func setFocusedRegion(_ region: FocusedRegion) {
        if focusedRegion != region {
            focusedRegion = region
        }
        // Post-presentation workspace restore can clear the published focus
        // fact without changing the native responder. Reassert observed focus
        // even for filter-to-list or repeated list entry.
        callbacks.onSidebarFocusChange(region != .unfocused)
    }
}
