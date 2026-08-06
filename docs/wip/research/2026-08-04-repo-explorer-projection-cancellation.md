# RepoExplorer Projection Cancellation Research

Date: 2026-08-04
Status: WIP research; not authoritative for the Repo sidebar grouping and menu change

## Boundary

This document preserves a projection-cancellation and lifecycle concern found
while designing the Repo sidebar grouping and context-menu change. That concern
is not required to deliver the requested labels, `By Pane` hierarchy, or
`Go to Pane` menus. It must not expand that feature's implementation or proof
scope.

Any future cancellation change requires its own confirmed problem statement,
scope, plan, tests, and performance evidence.

## Observed current behavior

- `RepoExplorerView` owns projection refresh and task bookkeeping.
- `RepoExplorerProjectionWorker` runs projection work in a detached task and
  supplies `Task.checkCancellation()` through an injected throwing closure.
- `RepoExplorerProjection` accepts cancellation checks at some stage
  boundaries.
- `RepoExplorerFilter` and shared `RepoPresentation` perform synchronous
  filtering, grouping, and sorting without an injected cancellation check.
- Cancelling an outer Swift task does not preempt CPU-bound synchronous work;
  cancellation is cooperative.

Relevant source locations:

- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerView.swift`
- `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjectionWorker.swift`
- `Sources/AgentStudio/Features/RepoExplorer/Models/RepoExplorerProjection.swift`
- `Sources/AgentStudio/Features/RepoExplorer/RepoExplorerFilter.swift`
- `Sources/AgentStudio/Core/Models/RepoPresentation.swift`

## Research conclusion

Swift task cancellation is cooperative:

- cancelling a task marks it cancelled but does not preempt synchronous loops;
- making a synchronous function `async` does not make its loops cancellable;
- detached work must be cancelled through its task handle and must explicitly
  inspect cancellation; and
- an injected throwing cancellation-check closure is a testable application
  pattern, not special Swift runtime behavior.

The codebase already uses the injected-check pattern in RepoExplorer and Inbox
projection code. Extending it through every proportional RepoExplorer loop and
shared Core grouping helper is technically possible, but it changes shared
function contracts and is broader than the sidebar UI request.

## Candidate direction for separate evaluation

One explored design would keep `RepoExplorerView` as the sole lifecycle owner
while allowing one active projection and one replaceable latest pending
request:

```text
request A       ──► start A
request B       ──► cancel A; retain pending B
request C       ──► replace B with pending C; do not start C
A acknowledged ──► start C
retire surface  ──► clear pending; do not start later work
```

A pure `RepoExplorerProjectionLifecycleReducer` was considered as a
deterministic policy seam. It would emit synchronous effects such as `start`,
`cancelActive`, or `none`, while `RepoExplorerView` continued to own tasks,
worker invocation, and result admission.

This direction is unaccepted research. It must not be implemented from this
document without confirming that the current behavior causes a real user or
performance problem and that this is the smallest valid correction.

## Questions before any future implementation

1. Is there a reproducible responsiveness or overlapping-work defect under a
   representative Repo sidebar workload?
2. Do existing generation-admission guards already contain the observable
   impact sufficiently?
3. Can a RepoExplorer-local correction solve the measured problem without
   changing shared `RepoPresentation` contracts?
4. Which loops materially exceed the cancellation-response budget?
5. What deterministic tests and measured workload prove improvement without
   wall-clock sleeps?

## Possible proof, if separately authorized

- a failing reproduction tied to a measured workload;
- deterministic cancellation checkpoints in only the loops proven material;
- A/B/C/acknowledgement/retirement lifecycle tests if lifecycle sequencing is
  part of the confirmed defect;
- strict-concurrency and focused projection tests;
- before/after workload measurements on identical topology; and
- implementation review verifying no second worker, queue, coordinator, or
  result-admission path was introduced.
