# Sidebar overlay and activation native proof

Source: `sidebar-keyboard-system` at `0444368a2` plus current sidebar core/terminal diff. The rendered app includes the presentation-value parameter correction. Later cold-focus reproduction tests do not alter that binary.

- App: isolated Debug `igj3`, PID 2621.
- Marker: `debug-observability-igj3-1789327111-92577`.
- `mise run run-debug-observability -- --detach` and `mise run verify-debug-observability`: exit 0; marker verified in Victoria, authenticated IPC.
- Current compile/quality evidence: `sidebar-chrome-reproof-*` under `tmp/sidebar-keyboard-design/`. Initial broad chrome gate: 106 tests/24 suites, exit 0. After parameter-only cleanup: 28 tests/5 suites, lint and diff check exit 0.

## Observed native behavior

CUA targeted the exact isolated bundle. Screenshots and AX observations are in the current session tool trace; no standalone screenshot files are claimed.

1. Entry from a terminal via Command-Shift-S shows P/R/F and first-nine overlays, the single keyboard glyph in the second toolbar row, and selected-row paint.
2. P switches to Panes; R switches to Repos, retaining list ownership. F focuses the real filter and suppresses list hints. Typing `navigation` and Return retains the query and restores working list hints/input.
3. Down selects the group separately from activation. Left selected its parent; subsequent collapse/expand interactions and Right moved to its first destination. Filtering preserves the non-collapsible-group guard. Automated tests retain the detailed idempotence proof.
4. Enter on the Files pane switched from another tab to the existing Layout 1 arrangement and displayed the real Bridge file canvas/tree. Sidebar hints disappeared. This proves native reveal and content, not nested WebKit DOM focus.
5. Direct digit 8, with the corresponding drawer pane in the accepted Panes list, selected the Terminal tab's Layout 2, expanded the parent drawer, displayed its terminal and placed the caret/focused AX scroll surface there. Existing pane remained visibly attached. No deferred drawer invariant repair was attempted.
6. Command-Shift-S followed by Escape returned focus to that drawer's terminal.
7. Repos first nine included `agent-studio.repo-bugs` as result 9. After scrolling the sidebar two pages so that destination was offscreen, digit 9 immediately opened its worktree in a new Default tab; the real shell prompt and tab title matched `repo-bugs`. Normal worktree activation may create a pane; this was not preview.
8. Overlays fit at both 436-point and 250-point sidebar widths. The existing accessible divider value successfully resized the sidebar; pointer drags had not changed it. Hints retain title/pin/chip columns, and the focus glyph remains separate from the Show Pinned control. Existing long-title truncation still applies at narrow width.

## Navigation capture measurement

The current marker's `agentstudio_performance_events_total` for `performance.sidebar.projection`, phase `request_build_mainactor`, was 8 before and 8 after 20 Down plus 20 Up inputs. Exact query timestamps: 1789327930 and 1789328046. Selection visibly moved; no destination was activated and no terminal command was entered. Readbacks are `sidebar-keys-capture-before.json` and `sidebar-keys-capture-after.json` under `tmp/sidebar-keyboard-design/`.

This supports no full sidebar capture caused by selection keys for this real app population. It is not a per-key latency percentile, broad stress benchmark or all-workloads performance claim. Background content updates still occurred.

## First-entry observation and subsequent correction

On the first entry after relaunch, when AX initially reported the filter focused, Command-Shift-S selected a row but hints were absent and P/F/Down had no effect. Clicking a terminal and entering again restored operation. Subsequent explicit F/Return succeeded. This prompted the source-backed correction below.

The first added reproduction used a separate TaskLocal CoreAtoms instance, while SwiftUI callbacks can resolve the shared production-style scope; its failed async case is not accepted as product root cause. The corrected shared-scope reproduction is being verified. Investigation: `tmp/debug-workflows/2026-09-13-agent-studio-sidebar-keyboard-system-sidebar-cold-focus/debug-investigation.md`.

Held preview and full aggregate annotation failure remain separate pending owner boundaries. Pinned traversal implementation and independent implementation review remain outstanding. This document does not declare PR readiness.

Additional native checks in the same marker: entered Management from the terminal (management controls and filled toolbar icon visible); Command-Shift-S retained Management and window focus. After leaving Management, Command-S hid the sidebar; Command-Shift-S restored the Panes surface with hints and list focus. Command-R from sidebar focus did not enter Management; this was not counted as Management-guard proof.

## Focus correction reproof

New binary: PID 78268, marker `debug-observability-igj3-1789329010-76301`. All `sidebar-focus-hydration-green-*` command result files report exit 0: formatting, 38 tests/6 suites, lint, diff, standard launch and observability verification. The underlying late-hydration sequence is documented in the debug investigation.

CUA initially observed the newly launched app in the background; keystrokes while traffic lights remained grey had no interpretable result and are not counted as failures or proof. After explicitly raising the exact debug window and focusing its filter, Command-Shift-S selected a real row and showed P/R/F hints. R switched to Repos. Repeating Command-Shift-S, F, typing `navigation`, direct Command-Shift-S from that filter, then P all worked with list ownership and visible hints. No intermediate click into a terminal was needed. The deterministic regressions independently exercise the post-presentation runtime focus reset from both filter and already-focused list.

The new local focus handshake repairs the reproduced stale-publication failure. This does not change UI persistence or claim broader startup timing benchmarks.
