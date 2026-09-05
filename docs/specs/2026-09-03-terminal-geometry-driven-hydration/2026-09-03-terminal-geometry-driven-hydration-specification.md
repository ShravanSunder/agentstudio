# Geometry-Driven Terminal Hydration Scheduling — Specification

Date: 2026-09-03

Specification identity: `SPEC-2026-09-03-TERMINAL-GEOMETRY-HYDRATION`

Requirements: [REQ-2026-09-03-TERMINAL-GEOMETRY-HYDRATION](2026-09-03-terminal-geometry-driven-hydration-requirements.md)

## Observable model

For this specification, terminal hydration has five observable states:

```text
persisted terminal
  -> waiting for safe geometry
  -> queued for hydration
  -> hydration in progress
  -> ready

Any obsolete queued/in-progress attempt may instead become replaced when a
new accepted workspace generation owns the pane.
```

Presentation state is a separate dimension. A ready terminal may be hidden; a
visible terminal may temporarily be waiting or queued. Visibility changes
priority. Safe geometry determines whether hydration can begin.

## Consumer and observable-surface boundary

This view answers: who can rely on the behavior, at which observable surfaces,
and what adjacent behavior remains outside the contract?

```text
returning end user
  |-- launch surface: selected terminals become usable first;
  |                   eligible hidden terminals become ready in bounded order
  |
  `-- reveal/layout surface: queued work is promoted;
                           ready terminals are reused at current dimensions

workspace operator
  `-- runtime surface: one bounded background admission at a time;
                       pane-correlated outcomes and no duplicate surfaces

                 [ Agent Studio terminal hydration ]
                         (opaque product boundary)

outside this contract:
  nonterminal hydration; visible rendering of hidden panes; new commands/UI;
  persistence/schema changes; session discovery; malformed-layout repair
```

## Normative requirements

### R1 — Geometry determines hydration eligibility

For every valid persisted terminal pane, Agent Studio MUST schedule hydration
when a safe non-empty frame is available or can be calculated from trusted
current container geometry and valid saved layout state.

The decision MUST NOT exclude a terminal solely because it is in an inactive
tab, minimized, inside a collapsed drawer, in a non-selected saved arrangement,
or residency-backgrounded. If one of those terminals has no unambiguous safe
frame, it follows R5 rather than receiving guessed geometry.

Success is observable when every geometry-eligible persisted terminal reaches
ready without first being revealed. Failure is observable when an otherwise
eligible terminal starts hydration only after tab selection or drawer opening.

Basis: U1, U2. Outcome: O1, O2.

### R2 — Foreground phases precede background work

At startup, Agent Studio MUST admit terminal hydration in this initial order:

1. visible main-layout terminals;
2. visible drawer terminals;
3. background main-layout terminals with safe geometry;
4. background drawer terminals with safe geometry.

The selected tab's visible main terminals MUST become interactive before
background hydration begins. Within each class, the active terminal precedes
its visible siblings where an active terminal exists.

Background work MUST NOT make the selected terminal wait for an unrelated
hidden terminal. Failure of one member MUST NOT prevent independent eligible
members from proceeding in their required order.

Basis: U1, U3. Outcome: O1.

### R3 — New visibility promotes queued work

When one visibility change makes one or more terminals visible while they are
queued for background hydration, Agent Studio MUST make the complete promoted
set the next admission batch after the admission currently in progress.
Promotion MUST apply across main and drawer background classes. The promoted
batch MUST be admitted in this tier order:

1. active main terminal;
2. visible main-terminal siblings;
3. active drawer terminal;
4. visible drawer-terminal siblings.

Within each tier, Agent Studio MUST preserve stable pre-promotion order. A
member's original ordinal in a background class MUST NOT move a later tier
ahead of an earlier tier in the promoted batch.

Agent Studio MUST NOT cancel an already-running terminal admission to satisfy
promotion. A newly visible terminal that is already hydrating or ready is not a
queued member of the promoted batch, and the visibility change MUST NOT start a
second hydration attempt for it.

Basis: U3, U4, U6. Outcome: O3, O5.

### R4 — Background concurrency is one

Agent Studio MUST allow no more than one non-visible terminal hydration
admission to be in progress at a time during startup restore. This bound also
applies while a promoted terminal waits for the current in-flight admission to
finish.

The app MAY yield between completed admissions, but it MUST preserve R2 and R3.
The concurrency bound MUST be observable under a real-size persisted workspace,
not inferred only from configured values.

Basis: U4. Outcome: O3, O6.

### R5 — Missing geometry defers and retries

If a valid persisted terminal has no safe frame and one cannot be calculated,
Agent Studio MUST skip surface creation for that attempt, keep the terminal's
canonical pane, membership, residency, and zmx-session identity unchanged, and
leave it eligible for a later geometry-triggered attempt.

The skipped terminal MUST NOT remain indefinitely presented as actively
preparing after the startup restore has settled. When a later layout or
visibility change supplies safe geometry, Agent Studio MUST retry it. If it
becomes visible, R3 governs its priority.

An invalid persisted composition remains subject to existing strict restore
rejection; this requirement does not repair or infer malformed layout state.

Basis: U5. Outcome: O4.

### R6 — Hydration is exact once per accepted generation

For one accepted workspace generation, each persisted terminal MUST have at
most one live hydration admission and at most one live terminal surface.
Hydration MUST use the exact stored `PaneId` and `ZmxSessionID` without
rewriting, deriving, or discovering a replacement identity.

Selecting a tab, expanding a drawer, changing arrangements, or receiving a
geometry update MUST reuse and resize or reattach an already ready terminal. It
MUST NOT create another surface or another zmx-backed terminal session for the
same pane.

If a newer accepted workspace generation replaces pending work, obsolete work
MUST NOT publish or attach a surface into the newer generation.

Basis: U6. Outcome: O2, O5.

### R7 — Bootstrap geometry must converge before display

A non-visible terminal MAY hydrate using safe approximate bootstrap dimensions
when exact on-screen dimensions are unavailable. Before that terminal is
presented to the user, Agent Studio MUST apply the current visible layout's
dimensions so the terminal does not appear with stale size or create a second
surface to correct it.

An empty, negative, or otherwise invalid frame MUST NOT be used for terminal
surface creation.

Basis: U1, U2, U6. Outcome: O2, O5.

## Observable contracts

### Startup restore contract

- Input/precondition: a strictly valid persisted workspace composition and
  trusted non-empty terminal container geometry.
- Postcondition: visible main terminals are admitted first; all other terminals
  with safe frames proceed under R2–R4; terminals without safe frames settle as
  deferred rather than creating a surface.
- Partial success: an independent terminal may be ready even if another
  terminal fails or lacks geometry. Failed or deferred panes remain canonical.
- Compatibility: existing strict composition rejection, pane/session identity,
  selected-tab focus, and terminal failure presentation remain unchanged.
- Cancellation/replacement: an obsolete generation cannot attach into its
  successor generation.

### Reveal and layout-change contract

- Input/precondition: a tab selection, arrangement selection, drawer expansion,
  or layout change makes a persisted terminal visible or supplies safe geometry.
- Ready terminal: reveal reuses the existing terminal and applies current
  geometry without new hydration.
- Queued terminal: it is promoted according to R3.
- Waiting terminal: it becomes queued when safe geometry exists; otherwise it
  stays deferred without false active-progress presentation.
- Failed terminal: existing explicit failure/retry behavior remains available;
  the layout change does not silently create a replacement session identity.

### Boundary examples

- A collapsed drawer child in the selected arrangement has calculable safe
  geometry. It hydrates in the background-drawer class before the drawer opens.
- An inactive tab's main terminal has a valid saved layout and trusted container
  size. It hydrates in the background-main class before tab selection.
- A terminal appears only in a saved arrangement whose frame cannot be safely
  chosen for the current layout. It stays deferred until arrangement selection
  supplies geometry; no frame is guessed.
- One visibility change reveals a queued active main terminal, a main sibling,
  an active drawer child, and a drawer sibling while another background
  terminal is hydrating. Their original background ordinals place both drawer
  terminals first. The in-flight terminal finishes, then the promoted batch is
  admitted as active main, main sibling, active drawer, drawer sibling; stable
  order is retained among any additional siblings in the same tier.
- A ready collapsed-drawer child is revealed. Its existing surface is resized
  and shown; no second zmx attach or terminal surface is created.

## Failure and negative space

- Geometry unavailability is retryable deferral, not evidence that the pane or
  persisted composition is invalid.
- Terminal surface creation or attachment failure remains an explicit terminal
  startup failure under the existing retry/presentation contract. It does not
  delete or rewrite canonical state and does not block unrelated panes.
- The ordering guarantee is for admission order; it does not promise identical
  completion times across terminals.
- A promoted queued set becomes the next ordered batch, but the specification
  provides no preemption or cancellation guarantee for work already in
  progress.
- The specification does not require hidden AppKit/SwiftUI view trees to be
  displayed or laid out onscreen. It requires the terminal runtime surface to be
  ready when safe geometry exists.
- The specification does not define geometry for invalid, unowned, or
  ambiguous persisted placement. Strict restore validity remains unchanged.
- No new command, UI control, persistence field, session discovery, terminal
  health protocol, or nonterminal hydration behavior is part of this contract.

## Cross-cutting obligations

- Reliability: pane identity, zmx-session identity, tab/drawer membership,
  residency, and valid saved arrangement state survive deferral and failure.
- Performance: non-visible admissions never exceed one concurrent operation;
  promotion adds no duplicate work; runtime evidence must show no admission
  burst when restoring a real-size workspace.
- Responsiveness: background hydration begins only after visible main and
  visible drawer phases, and newly visible queued work takes the next available
  admission position.
- Observability: proof must distinguish eligible, deferred, queued, promoted,
  in-progress, ready, failed, and replaced outcomes and correlate each outcome
  to one pane without exporting raw user content or paths.
- Privacy and security: no new user data or trust boundary is introduced;
  existing opaque typed zmx-session handling remains unchanged.
- Accessibility: no new interactive UI is introduced. Existing failure and
  retry controls retain their current accessibility contract.
- Platform compatibility: behavior targets the existing supported macOS,
  Ghostty, and zmx runtime boundary; no new external protocol is defined.

## Requirement-to-proof coverage

This view answers: which observable evidence distinguishes every material
requirement from a nominal implementation?

```text
U1,U2 -> P1 presentation gates hydration
      -> O1,O2 -> R1 -> C1 startup eligibility
      -> V1 automated classification + real debug restart/state inspection

U1,U3 -> P2 hidden work can delay or outlive visible demand
      -> O1,O3 -> R2,R3 -> C1 startup order + C2 reveal/promotion
      -> V2 automated ordering/promotion + runtime admission trace

U4    -> P3 many hidden terminals can create a startup burst
      -> O6 -> R4 -> C1 bounded startup
      -> V3 automated maximum-in-flight evidence + marker-scoped performance measurement

U5    -> P4 missing geometry permanently strands Preparing terminals
      -> O4 -> R5 -> C1 deferred startup + C2 geometry-triggered retry
      -> V4 automated state transition + real reveal/retry observation

U6    -> P5 reveal can repeat hydration or identity attachment
      -> O5 -> R6,R7 -> C1 startup + C2 reveal/current geometry
      -> V5 identity/surface state inspection + real zmx-backed restart/reveal evidence
```

## Proof obligations

- V1 — Automated behavior evidence covers active/inactive tabs, expanded and
  collapsed drawers, minimized panes, residency-backgrounded panes, calculable
  and uncomputable geometry, and valid non-selected arrangements. A real debug
  restart confirms geometry-eligible hidden terminals become ready before
  reveal.
- V2 — Automated behavior evidence proves visible-main before visible-drawer,
  initial background-main before background-drawer, and a multi-terminal
  visibility change promoting the complete queued set after the in-flight
  terminal. The promotion case uses opposing original background ordinals and
  proves active main, stable main siblings, active drawer, then stable drawer
  siblings; original ordinals cannot reverse those tiers. A runtime trace
  confirms the same batch ordering at admission without cancelling in-flight
  work.
- V3 — Automated state evidence records maximum simultaneous non-visible
  admissions as one. Marker-scoped performance evidence from the exact debug
  app process and a real-size persisted terminal fixture shows no duplicate
  admissions or unbounded startup hydration burst.
- V4 — Automated transition evidence proves missing geometry creates no surface,
  preserves canonical state, settles startup without a permanent active-progress
  state, and retries when safe geometry arrives. Real interaction confirms the
  pane becomes usable when later revealed.
- V5 — State and runtime evidence prove one pane identity, one exact stored zmx
  identity, at most one live surface, and no second hydration on tab selection,
  drawer expansion, or geometry refinement. The real debug-app journey includes
  restart with collapsed drawers and inactive tabs, then reveals each terminal.

The Program Design must expose proof seams for cross-class promotion,
generation replacement, safe-frame classification, and exact surface identity.
No required proof modality is currently waived.
