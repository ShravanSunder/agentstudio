# Drawer reveal: missing renderer reattachment

Review boundary: `96e7dbb..0e17351e1`. No correction is applied in this record.

**Assumed:** choosing an eligible arrangement through the existing switch action,
then opening/expanding as needed and focusing the child, exposes its actual renderer.

**Found:** minimize a drawer terminal in custom A while its physical drawer stays
expanded. The minimize action detaches its renderer. If custom B already contains
that child unminimized, committed focus selects B and skips both drawer toggle and
child expansion. The arrangement-switch transition lists contain main panes only,
so no child reattachment occurs. Existing-host restore skips this host; responder
assignment does not attach its renderer. Hidden renderers reject renderer focus.

**Consequence:** the written sequence does not fully realize R-A4. A selected pane
and an AppKit first responder are insufficient evidence that its terminal is exposed.
This is a structural design gap, not permission to quietly add another owner.

```text
custom A: child minimized → renderer detached
                 |
        committed focus chooses B
                 |
custom B: child unminimized, physical drawer already open
                 |
       toggle skipped / expand skipped
                 |
       responder selected; renderer still detached
```

Candidate correction: after arrangement selection, ensure the exact child receives
the existing reattachment effect even when no minimization change is needed. Keep
the chosen arrangement and all unrelated layouts. Use the existing App action and
lifecycle owner; no new atom, store, bus or general coordinator is proposed.

Proof must cover actual minimize→focus with an already-open drawer and two customs,
using a managed terminal surface. Assert hidden/active renderer membership and
renderer visibility/focus, followed by native proof when the GUI is unlocked.
The current Default-fallback integration test minimizes through an API that creates
a custom arrangement, so it does not establish a minimized Default child. Valid
persisted Default-child state needs its own fitting fixture if that branch is claimed.

Evidence:
- `Sources/AgentStudio/App/Panes/PaneCommittedFocusOperation.swift`: conditional toggle/expansion.
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActionExecution.swift`: switch main-pane transitions, minimize detach, expand reattach.
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ActiveTabRestore.swift`: existing-host skip.
- `Sources/AgentStudio/App/Coordination/WorkspaceSurfaceCoordinator+ViewHelpers.swift`: existing-host skip.
- `Sources/AgentStudio/App/Panes/PaneFocusExecutor.swift`: responder/runtime focus only.
- `Sources/AgentStudio/Features/Terminal/Ghostty/SurfaceManager+RendererState.swift`: active-only reconciliation and detached focus rejection.

Parent checked these load-bearing paths after the independent quality reviewer.
Native reproduction has not run: the GUI session is locked. The repository's
mental-model-break rule requires owner reconvergence before implementation.
