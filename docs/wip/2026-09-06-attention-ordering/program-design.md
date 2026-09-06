# Settled attention delivery — structural correction

This corrects the attention delivery structure against the existing requirements and
specification. It changes no definition of attention, notification policy, or atom ownership.

Requirements: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.perf-residuals/docs/specs/2026-09-05-observation-rearm-gap-sweep/2026-09-05-observation-rearm-gap-sweep-requirements.md`.
Specification: the adjacent `2026-09-05-observation-rearm-gap-sweep-specification.md`.
This realization covers R1–R3 and R5–R6. R4's complete observation-site inventory remains a
separate uncompleted obligation; this bounded correction does not claim that sweep is finished.

## Current call paths

At AgentStudio `9c2370020`, TerminalActivityRouter.start calls observeAttendedPane before
assigning busTask. The observation guard requires busTask, so the initial registration is skipped.
Its callback subsequently awaits consumeAttendedPaneTransition before registering again.
The consumer iterates a Set of previous/current IDs and awaits control delivery for each.

PaneFocusTracker defers publication followed by re-registration with no registration-generation
guard. Its tests use yield counts as completion evidence. The paused replacement publishes
inside willSet and changes AttendedPaneDerived; both contradict the settled latest-state contract.

```text
current router start → observe [guard fails] → install bus task
current change → deferred task → read attention → await controls → re-arm
                                                     ↑ wake gap
paused proposal → clear task slot → await controls
                  second task can begin here and overtake the first pair
```

## Selected ownership and tradeoff

The existing consumers remain the owners. PaneFocusTracker publishes settled non-nil gains;
TerminalActivityRouter translates settled previous/current attention into ordered activity
controls. AttendedPaneDerived and all atoms remain unchanged. No bus, store, event type,
coordinator responsibility, native surface API, or external setting is added.

A task per change does not serialize complete async operations. A queue of every mutation
would publish invisible intermediate attention. One coalesced settlement task per MainActor turn feeds an ordered queue of settled
transitions. One drain serializes that queue. The queue preserves distinct settled turns
while downstream delivery suspends; it never stores raw same-turn mutations.

## Tracker

A registration generation rejects obsolete callbacks. onChange synchronously checks that
registration and schedules at most one MainActor task; it never reads or publishes attention.
The task re-arms before reading the settled state and publishes only a changed non-nil gain.
Stop marks the tracker stopped, invalidates registrations, cancels the task, and finishes the
stream. No publication follows stop. Existing trace semantics include settled nil transitions.
An awaitPendingDelivery method observes the existing scheduled task for deterministic proof.

## Router

The router installs busTask before taking the initial attended snapshot and arming observation.
It owns one coalesced settlement task, an ordered array of captured settled transitions, and
one delivery task. Registration generations reject stale callbacks. A lifecycle epoch rejects
old settlement/delivery work after stop and restart. No state becomes ambient or persisted.

```text
atom mutation → valid onChange → schedule one settlement task for this turn
  settlement task → re-arm → read settled attention
                  → capture previous/current IDs, surfaces, before/after contexts
                  → append changed transition → start drain if absent

one delivery drain → oldest captured transition
                   → previous off [await existing ordered-control ingress]
                   → current on   [await existing ordered-control ingress]
                   → next captured transition, until queue empty

mutation while delivery awaits → another coalesced settlement task
                               → append its settled transition, never replace it
```

The settlement task updates the last captured attended ID when appending, rather than waiting
for delivery. Thus separate settled B→C and C→D turns enqueue both transitions even while
A→B is suspended. Same-turn B→C→D produces only the final D settlement. The task clears its
slot and re-arms before capturing, with no suspension in that synchronous segment.

Each queued transition owns captured IDs and before/after contexts. A newer live attention
value cannot relabel an older pair. Previous is delivered before current, never via a Set.
Before delivery, a captured surface mapping must still match the pane's current surface;
missing/replaced surfaces are skipped. The existing ordered-input sink retains its own identity
validation. Cancellation and lifecycle epoch are checked before issuing each control.

Start and stop themselves use one private lifecycle-operation task chain. Each public call
appends a MainActor operation that awaits its predecessor before executing performStart or
performStop. No predecessor is awaited while holding a lock. Duplicate starts see the existing
bus task and do nothing. A stop ordered after an in-flight start waits for configuration and
binding to finish before tearing it down; a subsequent start waits for the complete stop,
including projector reset and trace drain. An operation sequence number ensures an older
completion cannot clear a newer operation slot. This is local ordering of existing operations,
not a new coordinator or shared state owner.

performStop invalidates the lifecycle epoch and observation generation, cancels and joins
settlement/delivery tasks, clears queued transitions, then resets the projector. An already
issued control can finish, but no next control issues after invalidation. The epoch guards
old task cleanup as well as callbacks. The lifecycle chain prevents old reset from running
after newer configure. The final operation releases its task slot so completed operations
and captured references are not retained for the router's lifetime.

| Router state | Input | Result |
| --- | --- | --- |
| stopped | queued start executes | configure, bind, install bus, snapshot, arm |
| idle/running | valid wake | one settlement task scheduled |
| settling | capture differs | enqueue transition, ensure one drain |
| delivering | later turn settles | append ordered transition; no second drain |
| delivering | pair completes | next queued transition or idle |
| any | queued stop executes | invalidate, cancel/join, clear, reset, drain traces |
| stopping | start requested | waits behind complete stop |
| starting | stop requested | waits behind complete start |
| obsolete epoch | callback/completion | ignored |

Proof can await the settlement task separately from delivery: this establishes that C and D
settled on separate turns while an earlier delivery remains blocked. A delivery-idle waiter
joins only currently owned settlement/delivery work and is used after all test mutations.

## Proof boundary

Production control flow stays through Ghostty.ActionRouter.applyOrderedActivityControl,
its accumulator, the bound async input sink, and TerminalActivityProjector. Tests can replace
that existing binding after router start with a controlled sink, using a test binding ID and
always unbinding it afterward. No production injection API or DEBUG hook is required.

```text
real atoms → real AttendedPaneDerived → real router → real ordered ingress
                                                    → controlled async sink
                                                        captures contexts/order
                                                        suspends first control
```

Tests cover: first post-start transition; A→B→C without suspension emits only A-off/C-on;
two settled turns produce their complete sequence; suspended A→B followed by separately settled B→C and C→D produces
A-off/B-on/B-off/C-on/C-off/D-on with no overlap; stop during suspension prevents a later control;
start queued during stop cannot be reset by old cleanup; tracker settles same-turn gains, handles nil intervals, ignores obsolete work, and finishes.
Use bounded condition/event waits and join/cancel all tasks. A failed prerequisite stops that
test after cleanup rather than cascading into unbounded waits.

The existing projector integration must still prove that attended changes cancel only the
correct unseen-activity window. The synthetic sink proves ordering; it is not native smoke.

## Limits

This fixes neither the remaining Ghostty view retainer nor atom-family reclamation. The broad
site audit is still required for R4. Performance work stays one deferred task per settled tracker
turn and one active router drain; raw terminal samples remain contracted before MainActor.
