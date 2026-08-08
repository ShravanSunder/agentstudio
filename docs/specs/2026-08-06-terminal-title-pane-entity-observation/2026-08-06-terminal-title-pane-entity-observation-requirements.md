# Requirements: Terminal Title Cadence And Pane Observation Proportionality

Date: 2026-08-06

## Decision Authority And Evidence

The Agent Studio product owner authorized the desired behavior and delivery
boundary in the 2026-08-06 design conversation that followed the live
MainActor/OTLP investigation.

The following sources govern this Requirements record:

- **Normative:** the product-owner decisions in that conversation: title-only
  publication may wait up to one second; urgent local terminal presentation
  must not shorten that title window; those two title changes form one delivery
  slice; keyed pane observation forms a separate following slice.
- **Normative, retained where non-conflicting:**
  [Targeted Runtime Pressure Reduction](../2026-07-17-targeted-runtime-pressure-reduction/targeted-runtime-pressure-reduction.md),
  for terminal source admission, bounded latest-value contraction, exact-event
  ordering, replay/EventBus/IPC behavior, surface-lifetime safety, and immediate
  local presentation.
- **Observational:**
  [Agent Studio MainActor and OTEL runtime-pressure investigation](../../../tmp/debug-workflows/2026-08-06-agent-studio-slowdonw-mainactor-otel/debug-investigation.md),
  current source, Victoria telemetry, and process samples. These establish the
  current cost and trigger shape but do not authorize desired behavior.

## Affected People And Outcomes

### U1 — Interactive terminal user

- **Authority:** authorized by the product owner.
- **Priority:** first delivery slice.
- **Need:** terminal title churn must not repeatedly consume interaction-critical
  MainActor capacity.
- **Why it matters:** title traffic currently correlates one-for-one with broad
  tab/layout work and can coincide with visible input and navigation latency.
- **Evidence:** an 11-second live window contracted 350 raw title receipts into
  33 changed title publications, layouts, and tab-bar refreshes.

### U2 — Interactive terminal user

- **Authority:** authorized by the product owner and retained from the accepted
  terminal interaction contract.
- **Priority:** first delivery slice.
- **Need:** cursor shape, cursor visibility, scrollbar/activity presentation,
  and terminal-search feedback must remain promptly responsive even while title
  publication is delayed.
- **Why it matters:** these signals provide direct interaction feedback and have
  a different urgency from replaceable title metadata.

### U3 — IPC and runtime-event consumer

- **Authority:** retained from the accepted terminal runtime contract; not
  superseded by the new cadence decision.
- **Priority:** protected compatibility constraint.
- **Need:** the latest changed title must preserve existing per-surface ordering,
  sequence, replay, EventBus, IPC-wait, startup-readiness, and teardown safety.
- **Why it matters:** lowering publication frequency must not turn replaceable
  metadata into lost, stale, reordered, or cross-lifetime state.

### U4 — Interactive workspace user

- **Authority:** authorized by the product owner.
- **Priority:** second delivery slice.
- **Need:** changing one pane must invalidate only UI and capability presentation
  that can depend on that pane and changed fact.
- **Why it matters:** current keyed writes are consumed through whole-pane
  snapshots, causing unrelated tab, sidebar, and command-capability work to
  scale with the pane fleet.

### U5 — Agent Studio maintainer and operator

- **Authority:** authorized by the product owner and constrained by the current
  architecture contract.
- **Priority:** applies to both slices.
- **Need:** hot keyed reads must have attributable per-entity invalidation, while
  deliberate bulk snapshots remain available for cold persistence, restore,
  bridge, and measured fleet operations.
- **Why it matters:** performance proof must distinguish one affected entity
  from intentional whole-workspace work without weakening correctness.

## Confirmed Goal Boundary

The goal is two independently provable slices:

1. **Title cadence and urgency isolation:** use a fixed, non-sliding one-second
   maximum title-publication window that immediate local presentation cannot
   shorten. Preserve explicit exact-event ordering barriers and all existing
   title compatibility behavior.
2. **Pane observation proportionality:** make hot pane observation keyed and
   prevent title-only mutations from waking unrelated pane, tab, Repo Explorer,
   or command-capability presentation.

The first slice combines the previously discussed “PR1” and “PR2.” The second
slice is the previously discussed “PR3.” The numbering is conversational; the
durable boundary is the two semantic slices above.

## Protected Behavior And Non-Goals

- Do not redesign Ghostty callback ownership, payload copying, raw tag
  translation, or the exhaustive terminal-signal disposition vocabulary.
- Do not change exact commands/facts, their relative ordering, or the existing
  title sequence/replay/EventBus/IPC contract after contraction.
- Do not delay cursor, scrollbar/activity, or search presentation to the title
  cadence.
- Do not create an actor per pane, a generic mailbox, a second event bus, a
  durable title queue, or a new persistence/schema/migration system.
- Do not redesign tab, sidebar, or pane visuals.
- Do not weaken live command validation or make presentation enablement stale
  after capability-relevant structural changes.
- Do not treat bulk snapshots as forbidden. They remain valid for explicit cold
  or fleet-shaped work and must be identifiable as such.
- Git cadence, terminal-signal telemetry volume, general SwiftUI rendering, and
  unrelated MainActor hotspots are outside these two slices unless required to
  prove that the scoped invalidation edge is absent.

## Accepted Requirements Set

All five rows U1–U5 are normative-eligible and authorized. No accepted row is
superseded or deferred. The one-second title bound supersedes only the prior
250 ms title maximum; urgency isolation supersedes only the prior rule that an
immediate local-presentation drain may carry pending title metadata with it.
