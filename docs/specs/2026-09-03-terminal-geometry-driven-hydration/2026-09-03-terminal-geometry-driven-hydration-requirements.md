# Geometry-Driven Terminal Hydration Scheduling — Requirements

Date: 2026-09-03

Requirements identity: `REQ-2026-09-03-TERMINAL-GEOMETRY-HYDRATION`

## Why this change exists

Agent Studio persists terminal panes so their zmx sessions can survive an app
restart. Today, startup restores active main panes, including panes in inactive
tabs, but two valid classes remain unavailable until the user reveals them:

- collapsed drawer terminals are admitted without a frame and remain in a
  preparing state;
- residency-backgrounded terminals are excluded before startup scheduling.

The observable result is that selecting a previously hidden terminal can start
new hydration work instead of revealing a terminal that is already ready. This
makes restart behavior depend on presentation state rather than on whether the
app can safely restore the terminal.

## Authority and applicability

The product owner authorized the following requirements in the 2026-09-03
terminal-restore scheduling discussion. Each authorized row below records that
settled meaning. The owner assigned every row as required for this focused
design because the change repairs persisted terminal availability after restart
without delaying the currently visible workspace.

Current implementation and architecture documents are evidence about existing
behavior, not authority for the desired behavior:

- [Session Lifecycle Architecture](../../architecture/runtime/session_lifecycle.md)
  owns stable pane and zmx-session identity and separates residency from
  filesystem state.
- [Workspace Data Architecture](../../architecture/state/workspace_data_architecture.md#deferred-launch-restore)
  records the current trusted-geometry gate and startup ordering.
- [Foreground and Background Drawer Restore — Requirements](../2026-08-29-drawer-restore-requirements.md)
  remains authoritative for drawer-family persistence and strict composition
  validity, but its decision to defer hidden/background panes is superseded by
  U1–U6 below for terminal hydration only.
- Current composition preparation, startup mounting, terminal admission,
  scheduling, and geometry-resolution sources at origin/main `5c40ef7c8`
  establish the current behavior described above.

## Consumers and authorized needs

### U1 — Restored terminals are ready before reveal

- Affected class: a returning end user with persisted terminal panes.
- Authority state: authorized by the product owner on 2026-09-03.
- Priority: required, assigned by the product owner.
- Need: every valid persisted terminal that has safe non-empty layout dimensions, or
  whose dimensions can safely be calculated from valid saved layout and trusted
  container geometry, should hydrate during scheduled startup restore even when
  it is not currently visible.
- Why it matters: changing tabs or opening a drawer should reveal the existing
  terminal rather than begin terminal creation work.

### U2 — Geometry, not visibility or residency, decides eligibility

- Affected class: a returning end user with inactive-tab, collapsed-drawer, or
  residency-backgrounded terminal panes.
- Authority state: authorized by the product owner on 2026-09-03.
- Priority: required, assigned by the product owner.
- Need: visibility and residency may determine presentation and restore order,
  but they must not exclude an otherwise valid terminal from hydration when
  safe dimensions are available.
- Why it matters: a persisted placement label is not evidence that the user's
  terminal should stay unprepared.

### U3 — Visible work always wins

- Affected class: an end user interacting with the selected tab while startup
  restore continues.
- Authority state: authorized by the product owner on 2026-09-03.
- Priority: required, assigned by the product owner.
- Need: visible main terminals restore first, then visible drawer terminals. If
  a queued background terminal becomes visible, it becomes the next terminal
  admitted after work already in flight.
- Why it matters: background preparation must not delay the terminal the user
  is trying to use.

### U4 — Background hydration is bounded

- Affected classes: end users and operators of real workspaces with many
  persisted terminals.
- Authority state: authorized by the product owner on 2026-09-03.
- Priority: required, assigned by the product owner.
- Need: non-visible terminal hydration proceeds with a concurrency limit of one
  so restart does not create a CPU spike. An already-running admission is not
  cancelled merely because another pane becomes visible.
- Why it matters: the app must prepare the workspace without competing
  aggressively with foreground interaction.

### U5 — Missing geometry defers without stranding

- Affected class: a returning end user whose valid terminal cannot yet obtain a
  safe frame.
- Authority state: authorized by the product owner on 2026-09-03.
- Priority: required, assigned by the product owner.
- Need: the app skips that hydration attempt without deleting, hiding, or
  permanently stranding the terminal. When later layout or visibility supplies
  safe dimensions, the terminal becomes eligible again.
- Why it matters: geometry readiness is transient and must not be confused with
  invalid canonical state.

### U6 — One persisted terminal remains one runtime terminal

- Affected class: every returning end user with zmx-backed terminal panes.
- Authority state: authorized by the product owner on 2026-09-03.
- Priority: required, assigned by the product owner.
- Need: startup hydration and later reveal preserve the exact persisted pane and
  zmx-session identities. Revealing an already hydrated pane reuses and resizes
  its existing terminal surface; it does not create a duplicate terminal.
- Why it matters: terminal history, process identity, and resource usage depend
  on exact-once restoration.

## Current problem and protected constraints

- P1 — Presentation currently controls hydration eligibility for collapsed
  drawer terminals even when a safe bootstrap frame can be calculated.
- P2 — The current separated background categories cannot promote a terminal
  across category boundaries when user visibility changes during restore.
- P3 — A real-size workspace may contain many hidden terminals, so broader
  hydration must retain a hard resource bound rather than turning startup into
  an attachment burst.
- P4 — A terminal admitted without geometry can leave startup settled while its
  visible placeholder still reports Preparing and has no scheduled retry until
  a later user action.
- P5 — Extending eligibility must preserve the existing exact pane/session
  identity contract and must not make reveal or layout changes duplicate
  terminal creation.

## Terms at the product boundary

- **Hydrated terminal:** the persisted terminal's runtime surface is ready and
  attached to its exact stored zmx-session identity, whether or not its UI is
  currently presented.
- **Visible terminal:** a terminal currently presented in the selected tab's
  selected arrangement, including an eligible child of a currently visible,
  expanded drawer.
- **Background terminal:** any terminal that is not currently visible. This
  includes inactive-tab, minimized, collapsed-drawer, non-selected-arrangement,
  and residency-backgrounded terminals.
- **Safe dimensions:** a non-empty frame based on trusted current container
  geometry and valid saved layout state. The eventual visible layout may refine
  bootstrap geometry before presentation.

## Desired outcomes

- O1 — The selected tab becomes usable before background hydration, while every
  geometry-eligible persisted terminal subsequently becomes ready without being
  revealed first.
- O2 — Collapsed drawers and inactive tabs reveal already hydrated terminals.
- O3 — Visibility changes promote user-demanded work ahead of queued background
  work without interrupting an admission already in progress.
- O4 — A terminal without calculable geometry remains valid, leaves no false
  permanent preparing state, and retries when geometry becomes available.
- O5 — Restore performs no duplicate pane, zmx-session, terminal-surface, or
  hydration work for one persisted terminal.
- O6 — Real-size startup hydration stays bounded and produces no unbounded CPU
  or attachment burst.

## User journey and pain relationship

This view answers: where does the returning user currently pay the cost, and
what should become observably different?

```text
U1/U2/U3/U4/U5/U6

launch persisted workspace
  -> selected main terminal becomes usable first
  -> remaining geometry-eligible terminals hydrate one at a time in bounded order
  -> user selects an inactive tab or opens a collapsed drawer
       desired: existing hydrated terminal appears and receives final geometry
       current pain: terminal creation begins only now, or remains Preparing
  -> terminal lacked safe startup geometry
       desired: it stayed valid and is retried when geometry becomes available
       prohibited: deletion, duplicate creation, or permanent Preparing state
```

## Boundary and non-goals

This design is limited to startup and later geometry-triggered hydration of
persisted terminal panes. Agent Studio and its existing zmx/Ghostty integration
are the permitted system surface.

It does not authorize:

- changes to nonterminal pane startup behavior;
- a new atom, store, event type, coordinator, command, IPC method, persisted
  state, schema, or session-identity format;
- changes to pane residency meaning, tab/drawer membership, close/undo, or
  persistence validity;
- automatic creation of geometry for invalid or unowned layout state;
- eager visual rendering of hidden panes;
- cancellation of a terminal admission already in progress;
- changes to Git, filesystem observation, sidebar, Bridge, or repository
  lifecycle behavior;
- broad terminal-health reconciliation or zmx daemon discovery.

The acceptable complexity is a focused correction using the existing terminal
restore, geometry, and bounded scheduling foundation. Any new state owner,
persistence boundary, signaling subsystem, or public contract reopens the
design boundary and requires owner concurrence.

## Acceptable evidence

The owner accepts automated behavior and state evidence for eligibility,
ordering, promotion, bounded concurrency, retry, identity, and exact-once
hydration; a real debug-app restart journey for visible and hidden terminals;
and marker-scoped runtime/CPU evidence for a real-size persisted workspace.
Mocks alone are not sufficient evidence for zmx attachment or user-visible
reveal behavior.

## Open questions

No product decision remains open. Program Design must decide how the existing
restore pipeline derives safe frames and shares priority across queued terminals
without changing the outcomes above.
