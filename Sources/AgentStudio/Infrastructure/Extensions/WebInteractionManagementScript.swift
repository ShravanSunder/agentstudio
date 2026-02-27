import Foundation
import WebKit

/// JavaScript contract used to suppress WKWebView content interaction during
/// management mode while keeping pages live and rendering.
///
/// The script installs a stable window-scoped controller once, then toggles
/// behavior via `setBlocked(_)`:
/// - `pointer-events: none` on document root to suppress hover/cursor interaction
/// - capture-phase drag listener suppression to block in-page drop affordances
@MainActor
enum WebInteractionManagementScript {
    private static let stateVariable = "__agentStudioManagementInteraction"

    /// Persistent script injected at document start for each new page load.
    /// - Parameter blockInteraction: `true` to start a new document in blocked mode.
    static func makeUserScript(blockInteraction: Bool) -> WKUserScript {
        WKUserScript(
            source: makeBootstrapSource(blockInteraction: blockInteraction),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
    }

    /// Runtime command applied to the currently loaded document.
    static func makeRuntimeToggleSource(blockInteraction: Bool) -> String {
        """
        (function() {
            var state = window.\(stateVariable);
            if (state && typeof state.setBlocked === 'function') {
                state.setBlocked(\(blockInteraction ? "true" : "false"));
                return;
            }

            // Fallback for pages where bootstrap script has not yet initialized.
            var root = document.documentElement;
            if (!root) { return; }
            if (\(blockInteraction ? "true" : "false")) {
                root.style.pointerEvents = 'none';
            } else {
                root.style.removeProperty('pointer-events');
            }
        })();
        """
    }

    private static func makeBootstrapSource(blockInteraction: Bool) -> String {
        """
        (function() {
            var initialBlocked = \(blockInteraction ? "true" : "false");

            if (!window.\(stateVariable)) {
                var state = {
                    blocked: false,
                    dragHandler: null,
                    dragListenersInstalled: false
                };

                state.installDragListeners = function() {
                    if (state.dragListenersInstalled || !state.dragHandler) { return; }
                    document.addEventListener("dragenter", state.dragHandler, true);
                    document.addEventListener("dragover", state.dragHandler, true);
                    document.addEventListener("dragleave", state.dragHandler, true);
                    document.addEventListener("drop", state.dragHandler, true);
                    state.dragListenersInstalled = true;
                };

                state.removeDragListeners = function() {
                    if (!state.dragListenersInstalled || !state.dragHandler) { return; }
                    document.removeEventListener("dragenter", state.dragHandler, true);
                    document.removeEventListener("dragover", state.dragHandler, true);
                    document.removeEventListener("dragleave", state.dragHandler, true);
                    document.removeEventListener("drop", state.dragHandler, true);
                    state.dragListenersInstalled = false;
                };

                state.enable = function() {
                    var doc = document;
                    var root = doc.documentElement;
                    if (!doc || !root) {
                        state.blocked = true;
                        return;
                    }

                    if (!Object.prototype.hasOwnProperty.call(root.dataset, "agentStudioPrevPointerEvents")) {
                        root.dataset.agentStudioPrevPointerEvents = root.style.pointerEvents || "";
                    }
                    root.style.pointerEvents = "none";

                    if (!state.dragHandler) {
                        state.dragHandler = function(event) {
                            event.preventDefault();
                            event.stopPropagation();
                        };
                    }
                    state.installDragListeners();

                    state.blocked = true;
                };

                state.disable = function() {
                    var doc = document;
                    var root = doc.documentElement;
                    if (doc && root) {
                        var previous = root.dataset.agentStudioPrevPointerEvents;
                        if (previous === undefined || previous.length === 0) {
                            root.style.removeProperty("pointer-events");
                        } else {
                            root.style.pointerEvents = previous;
                        }
                        delete root.dataset.agentStudioPrevPointerEvents;
                    }

                    state.removeDragListeners();

                    state.blocked = false;
                };

                state.setBlocked = function(blocked) {
                    if (blocked) {
                        state.enable();
                    } else {
                        state.disable();
                    }
                };

                window.\(stateVariable) = state;
            }

            window.\(stateVariable).setBlocked(initialBlocked);
        })();
        """
    }
}
