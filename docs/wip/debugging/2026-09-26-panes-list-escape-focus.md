# Panes list Escape focus diagnosis — 2026-09-26

## 2026-09-28 production-path correction

The original host-only test did not exercise the window controller's held pane preview. A new
`MainSplitViewControllerCompositeCommandTests.panesEscapeReturnsToMountedPane` test uses the
Panes surface, a mounted terminal responder, the real `NSWindow.sendEvent` Escape path, and an
active held preview. It failed before the correction: the saved terminal responder regained first
responder status, but `HeldPanePreviewState.isHeld` remained true. The shared
`restoreSidebarReturnFocusOrigin()` method, used by both Escape's callback and a second
focus-sidebar command, restored the responder without cancelling the preview. It now calls the
existing `cancelIfHeld()` operation before restoring the responder. This makes both exit routes
settle the same focus and preview state.

The owner's live observation that Escape did not return typing still needs a post-fix native
check. The current PR A debug window is on the primary display; Peekaboo could capture it but
reported the window unavailable for resize/move, and System Events exposed no AX windows for
that process. We did not send keys to the primary display. A separate, already-running debug
instance on the second display belongs to another task and was left untouched. This limits the
claim to the production-window test until a PID-targeted second-display run is available.

## Question

R32 requires Escape while the Panes list has keyboard focus to leave list navigation and return typing to the previous pane. The owner reported that Escape did not return focus.

## Native key-path evidence

`RepoExplorerListKeyboardIntegrationTests.nativeEscapeReturnsFocusFromPanesList` creates a real `NSWindow` and `RepoExplorerMaterializationHost`, applies a Panes row snapshot, makes the list host first responder, and sends Escape through `NSWindow.sendEvent`. It asserts that the return-focus callback runs once, the field editor of the destination text field becomes first responder, and list keyboard mode ends. The focused test passed (1 test, 0 failures, exit 0).

The first test assertion compared `NSWindow.firstResponder` with the `NSTextField` itself and failed. AppKit correctly made the text field's `NSTextView` field editor first responder; replacing the assertion with `textField.currentEditor()` made the native-path test pass. That failure was an incorrect test oracle, not a reproduction of the reported bug.

## Code path and conclusion

`RepoExplorerMaterializationHost.keyDown` decodes the key and calls `handleListKeyboardAction(.returnFocus)`; that calls `RepoExplorerKeyboardInteraction.returnFromList()`, which invokes `onReturnFocusRequest`. In production, `RepoExplorerView` supplies `onRefocusActivePane`, and `MainSplitViewController` binds it to `restoreSidebarReturnFocusOrigin()`.

The native host path **did not reproduce** the reported failure. This test proves key delivery and callback invocation through the real AppKit window. It does not exercise `MainSplitViewController`'s saved responder, pane mount, or preview state. Those production boundaries remain possible causes and need a separate end-to-end reproduction if the symptom persists. No host or focus implementation was changed in this slice.
