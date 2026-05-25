# Adversarial Review — Navigation/Arrangement/Scrollback Shortcuts Plan

Plan reviewed: `docs/superpowers/plans/2026-05-23-navigation-arrangement-scrollback-shortcuts.md`
Reviewers: Gemini 3.x + Codex GPT-5.x (parallel, via counsel-reviewer)
Date: 2026-05-23

## Verdict: SHIP-WITH-FIXES

Two concrete blockers, both mechanical (not architectural). Plan's research and structure are sound. Ghostty API claims verified against vendored source.

---

## Blockers (must fix in the plan file before execution)

### B1. `dispatchRuntimeCommand` API mismatch — Task 5 Step 8, plan lines 1163–1171

Plan writes:

```swift
_ = await self.dispatchRuntimeCommand(
    .terminal(.jumpToPrompt(delta: delta)),
    paneId: paneId
)
```

Actual signature (`Sources/AgentStudio/App/Coordination/PaneCoordinator+RuntimeDispatch.swift:5-10`):

```swift
func dispatchRuntimeCommand(
    _ command: RuntimeCommand,
    target: RuntimeCommandTarget,
    correlationId: UUID? = nil
) async -> ActionResult
```

And the existing `.scrollToBottom` site uses:

```swift
target: .pane(PaneId(uuid: paneId))
```

with `Task { @MainActor [weak self] in ... }`. The plan is missing both `target:` shape and `@MainActor`. Implementing as written will not compile.

**Fix:** replace the snippet at plan line 1163–1171 with the form that matches `.scrollToBottom` exactly (use that case as the template — copy its `@MainActor` annotation too).

### B2. `makeHarness` signature update is hand-waved — Task 4 Step 1, plan line 826

Plan says "If `makeHarness` does not accept `arrangementPanelPresentation`, update the test harness". It doesn't — current signature in `Tests/.../PaneTabViewControllerCommandTestSupport.swift` (lines ~36–44) lacks the parameter. Without an explicit edit instruction, the executor may either skip the update (compile fails) or guess at placement.

**Fix:** add an explicit Step in Task 4 that edits `PaneTabViewControllerCommandTestSupport.swift`:
- Add `arrangementPanelPresentation: ArrangementPanelPresentationAtom = .init()` to `makePaneTabViewControllerCommandHarness`.
- Pass it through to the `PaneTabViewController(...)` constructor.

---

## Soft concerns (note, don't gate)

### S1. Multi-window race on `ArrangementPanelPresentationAtom` (Gemini)

`pendingRequest` is a single slot, not a queue. Two rapid ⌘⌥I in different windows → second overwrites first; first window's request is silently dropped. Acceptable for v1; revisit if real users hit it.

### S2. Silent swallow when policy rejects host-owned chord (Codex)

R10 is the explicit anti-leak rule, so this is intentional defense-in-depth. The user-visible failure mode (chord eaten, no feedback) is mitigated because the only hard-coded suppressed trigger is ⌘K itself; everything else still flows through the policy gate before being eaten. Accepted tradeoff.

### S3. `jump_to_prompt` requires shell-side OSC 133

Ghostty's `jump_to_prompt` only works when the shell emits OSC 133 semantic prompt sequences (zsh `precmd` hook, bash 5.1+ shell integration, etc.). Without it, the binding silently no-ops. Not an Agent Studio bug, but worth a one-liner in the plan's Copy-Since-Last-Prompt scope section so the executor doesn't chase a phantom failure.

---

## Confirmed-correct claims (stop worrying about these)

| Claim | Verified at |
|---|---|
| Ghostty accepts `jump_to_prompt:-1`/`:1` with signed integer delta | `vendor/ghostty/src/input/Binding.zig:490, 1350, 3346-3353` |
| `ghostty_surface_binding_action` signature `(surface, c-string, length)` | `vendor/ghostty/include/ghostty.h:1123` |
| `WindowLifecycleAtom.focusedWindowId` + `keyWindowId` exist | `WindowLifecycleAtom.swift:8-9` |
| `AppShortcut.X.trigger` is a computed property | `AppShortcut.swift:424` |
| Swift mixed-arity combined-case pattern with shared bindings + `_` is valid | Swift 6 grammar |
| Existing `.scrollToBottom` already uses `Task { @MainActor [weak self] in ... }` | `PaneCoordinator+ActionExecution.swift` ~340-347 |
| `ActionValidator` already combines cases via shared bindings | `ActionValidator.swift:205-208` |
| `commandBarSurface` + `transientKeyboardSurface` registered | `AtomRegistry.swift:21-22, 45-46, 79-80` |
| `paneInboxPresentationState` validates one-shot-presentation atom pattern | `AtomRegistry.swift:18` |

---

## Unverifiable (out of plan scope)

- Menu bar updates — no main menu xib found, app appears keyboard-only. Likely nothing to update.
- User-customizable shortcuts — current `AppShortcut` is an enum, no persistence layer.
- Shell integration setup — caller's responsibility, see S3.

---

## Concrete edits to apply to the plan

1. **Plan lines 1163–1171** — rewrite the `.jumpToPrompt` dispatch snippet to match the actual `.scrollToBottom` template (target:.pane, @MainActor on Task).
2. **Plan Task 4** — add an explicit step editing `PaneTabViewControllerCommandTestSupport.swift` to extend `makeHarness` with `arrangementPanelPresentation`.
3. **Plan Copy-Since-Last-Prompt section (lines ~36–42)** — add a one-line note that `jump_to_prompt` requires OSC 133 shell integration.

After these, the plan is executable.
