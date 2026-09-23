# Terminal navigation command path

Inputs: [Requirements U17](../../wip/2026-09-11-keyboard-navigation/requirements.md)
and the [Specification](specification.md).

## Owners and cutover

    AppShortcut / AppCommandSpec
       -> existing Ghostty source-key or AppKit key ingress
       -> AppShortcutDispatchPolicy / AppCommandDispatcher
       -> PaneTabViewController (resolve current or explicit terminal target)
       -> PaneRuntimeCommand.terminal
       -> TerminalRuntime / TerminalSurfaceCommandDispatching
       -> SurfaceManager -> TerminalSurfaceAction -> ghostty_surface_binding_action
       -> Ghostty scroll_viewport / jump_to_prompt

Keep the existing command, routing, runtime and effect owners. Retain AppCommand
scrollToBottom, scrollPageUp, scrollPageDown, jumpToPreviousPrompt and jumpToNextPrompt.
Hard-rename the current unpublished scrollQuarterPageUp/Down AppCommand and
AppShortcut identities to scrollSmallStepUp/Down. Remove the old raw identities
without aliases or compatibility paths, including their catalog/IPC discoverability
and execution. Carry the new names through every exhaustive shell, pane, shortcut,
interactive and IPC projection. Preserve the existing interactive exposure, required
pane target, terminalInputWrite privilege and no-argument contract. Terminal shortcuts
remain terminalAppOwned, with explicit command-bar display projections.

AppPolicies.TerminalNavigation retains pageFraction 0.9 and changes smallStepFraction
from 0.25 to exactly 0.33. Update the selected chords and catalog copy together.
PaneTabViewController continues mapping direction to a signed fraction and submitting
the existing targeted runtime command. Retain the already implemented
TerminalCommand.scrollPageFractional(fraction: Double), matching dispatcher method
and TerminalSurfaceAction case end-to-end. Do not restore the removed runtime
scrollPageUp branch. The AppCommand identity scrollPageUp remains the user-facing
upward large-step action; it is not a second runtime implementation.

SurfaceManager performs the existing surface lookup and C binding-action dispatch.
TerminalSurfaceAction formats scroll_page_fractional with the signed amount. Bottom
and prompt actions keep their existing Ghostty action serialization and effect path.
Ghostty, not AppKit, computes viewport rows and truncates fractional row movement.

## State, failure and concurrency

AppShortcutDispatchPolicy retains its existing Management allowance for terminal-owned
shortcuts. Sidebar and blocked transient ownership still reject dispatch. Extend only
terminal-command classification and the seven exact bindings; do not add a Management
block or change focusSidebar's separate Management exclusion. Policy and ingress tests
cover both the existing allowed Management path and blocked sidebar/transient paths.

No new atom, store, event, coordinator, observer, cache, focus mode or scheduling
hop. Existing main-thread key/focus dispatch invokes the embedded action API; no
Agent Studio viewport calculation, output scan or sidebar derivation is introduced.
Runtime commands preserve their existing target validation, active-surface access,
result mapping and command correlation. A missing surface or rejected Ghostty action
returns the existing failure result; it never opens a new terminal or retries in a
different pane. Capture and preserve the original terminal source identity through
key routing, particularly when focus is in a drawer.

This command-only change needs no persistence migration or vendor modification.
The default Ghostty profile is not a second shortcut authority: Agent Studio's
owned-key path consumes its bindings before terminal fallback. Existing profile
configuration and shell-marker propagation are preserved.

## Proof boundaries

Catalog/decoder tests establish unique bindings, exact terminal context, replacement
hints and unassigned Option-Shift-I/K. Real AppKit-key and Ghostty-source ingress tests
establish ownership/targeting and consumption. Runtime tests establish the signed
fraction reaches the surface dispatcher, and TerminalSurfaceAction tests establish
the exact Ghostty action string. Isolated native terminal proof establishes scrolling
amount, clamping, bottom and marked prompts through the actual embedded renderer.

Source basis: current AppShortcut/DispatchPolicy/catalog, PaneTabViewController terminal
dispatch, TerminalRuntime, TerminalSurfaceActionPerforming and SurfaceManager terminal
actions. Pinned Ghostty 82232ecde src/input/Binding.zig defines fractional f32 actions;
src/Surface.zig scales current grid rows, truncates, and queues scroll_viewport.
No alternative scroll engine is needed; adding one would duplicate Ghostty ownership.
