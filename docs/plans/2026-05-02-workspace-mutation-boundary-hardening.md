# Workspace mutation boundary hardening — Implementation Plan

> **For agentic workers:** Execute this as one ticket with one canonical plan. Keep design truth here, keep progress tracking in `LUNA-375`.

**Goal:** Bring workspace mutation flow back into alignment with the current architecture rules by making structural pane/tab mutations share one validated ingress, making workspace graph assembly come from one composition root, and making empty-tab cleanup a single-owner invariant.

**Why this plan exists:** current `main` still has three related boundary drifts:

1. UI structural actions are validator-gated, but terminal-originated structural runtime actions still call `PaneCoordinator.execute(...)` directly.
2. `WorkspaceStore` still synthesizes fallback `WorkspaceTabLayoutAtom` / `WorkspaceMutationCoordinator` instances even though `AtomRegistry` already assembles that graph.
3. Empty-tab pruning still exists in both `WorkspaceTabLayoutAtom` and `WorkspaceMutationCoordinator`.

These are not three unrelated cleanup items. They all point at the same architectural problem: mutation boundaries are expressed in more than one place.

**Architecture target:** one shared validated dispatcher for structural `PaneActionCommand`, one direct fact-sync path for runtime metadata, one composition root for the workspace graph, and one owner for tab-layout cleanup invariants.

**Out of scope:** splitting `PaneCoordinator` into dedicated collaborators such as `RuntimeEventPump` / `RuntimeActionMapper`, or performance-driven `RepoCacheAtom` changes without profiling evidence.

---

## Current state and evidence

### Structural mutation ingress is still split

- `Sources/AgentStudio/App/Commands/ActionExecutor.swift`
  - `execute(_ action: PaneActionCommand)` builds `ActionStateSnapshot`
  - validates via `WorkspaceCommandValidator`
  - delegates only validated actions to `PaneCoordinator`
- `Sources/AgentStudio/App/Panes/PaneTabViewController.swift`
  - still performs controller-side validation / `canExecute` checks
  - rebuilds overlapping snapshots for command routing and preflight checks
- `Sources/AgentStudio/App/Coordination/PaneCoordinator.swift`
  - `handleTerminalRuntimeEvent(...)` still maps structural Ghostty events directly to `execute(...)`
  - metadata facts (`titleChanged`, `tabTitleChanged`, `cwdChanged`) already use direct atom updates

### Workspace graph assembly is still duplicated

- `Sources/AgentStudio/Infrastructure/AtomLib/AtomRegistry.swift`
  - assembles `WorkspaceTabLayoutAtom`
  - optionally assembles `WorkspaceMutationCoordinator`
- `Sources/AgentStudio/Core/State/MainActor/Persistence/WorkspaceStore.swift`
  - still accepts optional `tabLayoutAtom` and `mutationCoordinator`
  - still constructs fallback instances when omitted
- Tests still have many direct `WorkspaceStore()` call sites, which preserves graph drift in test-only composition paths

### Layout cleanup invariant is still duplicated

- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceTabLayoutAtom.swift`
  - owns `removeEmptyTabs()`
- `Sources/AgentStudio/Core/State/MainActor/Atoms/WorkspaceMutationCoordinator.swift`
  - also owns `removeEmptyTabs()`

### Relevant architecture rules

- `docs/architecture/README.md`
  - workspace mutation is validator-gated `PaneActionCommand`
  - runtime fact bus is for facts, never commands
- `docs/architecture/component_architecture.md`
  - coordinators sequence work; they do not own domain logic
- `docs/architecture/workspace_data_architecture.md`
  - bus carries facts, not instructions
- `docs/architecture/pane_runtime_architecture.md`
  - terminal runtime events are explicitly categorized into coordinator-consumed facts and command-like events

---

## Section 1 — Unify structural mutation ingress

**Problem:** structural actions currently enter through overlapping validation surfaces:

- `ActionExecutor`
- `PaneTabViewController`
- drawer / drag-drop preflight validation
- direct runtime event mapping in `PaneCoordinator`

That duplicates snapshot assembly and makes it possible for UI and runtime structural actions to drift apart semantically.

**Target shape:**

1. Introduce one shared validated structural dispatcher.
2. Give it one snapshot-building path.
3. Route structural runtime actions through that dispatcher.
4. Keep metadata facts out of that dispatcher.

**Required distinction:**

- **Structural actions** must go through the validated dispatcher.
  - examples: `insertPane`, `closeTab`, `moveTab`, `equalizePanes`, `toggleSplitZoom`, drawer structural commands
- **Metadata facts** must remain direct fact sync.
  - examples: `titleChanged`, `tabTitleChanged`, `cwdChanged`

**Implementation notes:**

- The dispatcher can stay in `ActionExecutor`, or be extracted into a small shared helper used by `ActionExecutor`, `PaneTabViewController`, and runtime-originated structural routing.
- `PaneTabViewController` should keep lightweight `canExecute` behavior where needed, but it should not own its own divergent structural snapshot semantics.
- `DrawerCommandValidator` remains the drawer rule engine; the refactor is about who builds and routes the validated action path, not about deleting drawer-specific validation.

**Acceptance for this section:**

- UI structural actions and runtime structural actions pass through the same validation / canonicalization path before execution.
- No command-like runtime events are sent over the event bus as commands.
- Metadata facts still bypass command validation and update atoms directly.

---

## Section 2 — Make workspace graph assembly single-root

**Problem:** `AtomRegistry` already acts like the composition root, but `WorkspaceStore` still quietly assembles fallback graph pieces when collaborators are not injected.

That makes app boot and test boot follow different mental models.

**Target shape:**

1. `AtomRegistry` remains the single assembler for the workspace graph.
2. `WorkspaceStore` becomes a pure persistence wrapper over already-assembled collaborators.
3. Tests and previews use shared test graph factories instead of `WorkspaceStore()` fallback assembly.

**Implementation notes:**

- Keep constructor injection, but make `tabLayoutAtom` and `mutationCoordinator` required instead of optional.
- If helper ergonomics are needed for tests, add explicit factories in test support rather than optional runtime assembly in production.
- Preserve current restore / persist behavior; this section is about graph construction, not persistence semantics.

**Acceptance for this section:**

- Production and test composition use the same graph shape.
- `WorkspaceStore` no longer constructs fallback `WorkspaceTabLayoutAtom` / `WorkspaceMutationCoordinator`.
- A shared graph factory exists for tests / previews that need convenience.

---

## Section 3 — Make layout cleanup invariant single-owner

**Problem:** empty-tab pruning exists in both `WorkspaceTabLayoutAtom` and `WorkspaceMutationCoordinator`.

That means one layout invariant can drift in two places.

**Target shape:**

1. `WorkspaceTabLayoutAtom` owns empty-tab cleanup.
2. `WorkspaceMutationCoordinator` performs sequencing only.
3. Any call site that needs post-mutation cleanup asks layout to perform it, rather than re-encoding the rule.

**Implementation notes:**

- Prefer keeping cleanup near layout mutation because the invariant is layout-derived, not orchestration-derived.
- `WorkspaceMutationCoordinator` may still trigger cleanup indirectly, but must not own a separate implementation.

**Acceptance for this section:**

- There is only one implementation of empty-tab pruning.
- Tests assert the invariant through the layout owner, not through duplicated helper behavior.

---

## Execution order

1. Land Section 1 first.
   - It has the highest architectural value and reduces future drift while other work continues.
2. Land Section 2 next.
   - It removes the graph ambiguity that would otherwise keep reappearing in tests and helper paths.
3. Land Section 3 last, or fold it into Section 2 if the touched files already overlap naturally.
   - It is important, but narrower and easier once graph ownership is clean.

This stays one ticket because all three sections are facets of the same boundary-hardening change and share the same acceptance story.

---

## Verification

Before calling this ticket done:

- Run targeted tests for:
  - action validation
  - pane/tab controller command routing
  - runtime-originated structural action handling
  - workspace store / graph assembly helpers
  - tab cleanup invariants
- Run the full repo verification loop required by the project:
  - `mise run test`
  - `mise run lint`
- Confirm the final code shape still matches:
  - validator-gated workspace mutation plane
  - facts-not-commands runtime event plane
  - coordinator as sequencing boundary, not invariant owner

---

## Deferred follow-up

Once this ticket lands cleanly, a separate follow-up may extract:

- `RuntimeEventPump`
- `RuntimeActionMapper`
- smaller `PaneCoordinator` collaborators

That follow-up should only start after the structural ingress is unified, otherwise it risks freezing the current drift into more files instead of removing it.
