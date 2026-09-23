# Terminal family design review

Scope U17; distinct Requirements home plus Specification and Program Design under
docs/specs/2026-09-13-terminal-keyboard-navigation. One bounded independent round:
terminal_design_review (mode-complete), then terminal_design_dispel (scope defense).

Reviewer identified ambiguous Management wording. Parent read the existing policy:
terminalAppOwned commands remain allowed in Management; focusSidebar is the separate
exception. U17 did not request a new block. Parent clarified T3, the journey and
Program Design to preserve that existing allowance and blocked sidebar/transient
paths. Dispel confirmed the proposed new block would weaken the preserved contract.
No new owner decision was required; no second design round or recovery used.

Parent verified bindings, AppCommand catalog and IPC classification, pane-target
dispatch, TerminalCommand, TerminalRuntime, SurfaceManager and action serialization,
plus pinned Ghostty Binding.zig/Surface.zig fractional semantics. Result: bounded
terminal design ready for implementation. No whole-sidebar or runtime-proof claim.

Initial RED: terminal-map-red.log and companion result JSON, exit 1, one test with
seven expected mapping failures. Four old bindings resolve to the wrong action;
three new bindings are absent. Evidence lives under tmp/sidebar-keyboard-design.
