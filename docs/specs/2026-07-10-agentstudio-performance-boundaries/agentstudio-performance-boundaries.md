# AgentStudio Performance Boundaries

Date: 2026-07-10
Status: accepted for implementation-plan creation after focused adversarial review
Scope: parent pre-plan contract for filesystem pressure and terminal interaction
Baseline: `ghostty-performance` at `cd47c511`

## Product Intent

AgentStudio is an interactive terminal workspace first. Background discovery,
filesystem churn, Git projection, semantic event delivery, persistence, Bridge
refresh, and terminal intelligence must not make typing, cursor movement, pane
switching, or current terminal presentation feel frozen.

Responsiveness cannot be purchased by silently losing correctness. Under
pressure, source hints and presentation samples may contract, but exact semantic
facts, recovery obligations, canonical topology, secure-input protection, and
terminal lifecycle must remain correct and eventually converge.

This parent contract exists so a planner does not have to infer shared rules by
comparing two long sibling specs. It owns cross-domain vocabulary, dependency
direction, safe defaults, and the combined proof boundary. The child specs own
their domain-specific requirements:

- [Watched-Folder Admission and MainActor Fairness](../2026-07-09-watched-folder-admission-mainactor-fairness/watched-folder-admission-mainactor-fairness.md)
- [Ghostty Host Boundary and Terminal Interaction Fairness](../2026-07-09-ghostty-terminal-interaction-fairness/ghostty-terminal-interaction-fairness.md)

## Shared Mental Model

```text
untrusted/high-rate source
  -> bounded source-owned admission
  -> contraction plus exact recovery obligation
  -> off-main scheduling / scan / join / projection / serialization
  -> semantic fact or typed mutation
  -> small synchronous MainActor application
  -> local observable state and presentation

interactive input
  -> AppKit MainActor handler
  -> direct synchronous libghostty call
  -> Ghostty-owned PTY / VT / renderer work
  -> measured response / frame-layer-publication seam + native visible proof
```

Actor isolation is necessary for data-race safety but insufficient for
performance. Every pressure-bearing boundary must also declare admission,
capacity, contraction, ordering, recovery, generation, consumers, sensitivity,
and telemetry.

## Boundary / Separability Map

```text
filesystem source boundary
  owns: FSEvent callback capture, repair debt, scan scheduling
  exposes: generation-bearing observations, repairs, semantic facts

                    typed semantic topics
                              |
                              v
shared runtime transport ----------------------> named projectors/coordinators
  owns: topic interest, replay, fanout, lag       own: domain joins/scheduling
  does not own: raw samples, joins, UI mutation   expose: typed apply batches

                              |
                              v
MainActor last mile
  owns: canonical observable state and direct AppKit calls
  accepts: changed-key mutations and bounded current-state samples
  rejects: scans, fleet joins, retry queues, serialization, Bridge builds

Ghostty host boundary
  owns: callback lifetime, tick/action admission, surface host truth
  exposes: pane-local samples, snapshots, targeted intents, semantic facts
  does not own: VT parsing, Metal rendering, global raw-event processing

shared performance harness
  owns: one run identity, clocks/correlation, scenario manifest, evidence
  combines: watched pressure factors + terminal interaction stages
```

## Shared Pressure Stream Contract

Every high-cardinality or latency-sensitive path has an inspectable declaration
with these fields. Concrete symbol names may vary; semantics may not.

| Field | Contract |
| --- | --- |
| owner | one component mutates queue state and acknowledges recovery |
| input | typed observation, sample, fact, intent, mutation, or diagnostic |
| isolation | callback thread, actor, MainActor, or synchronous caller |
| capacity | maximum items, keys, and/or bytes; hard versus diagnostic |
| admission | exact, latest-by-key, accumulated, debounced, sampled, or rejected |
| overflow | contracted data and the durable recovery obligation replacing it |
| ordering | per source, key, generation, semantic stream, or intentionally none |
| replay | none, current snapshot, bounded fact history, or authoritative rebuild |
| consumers | named owners/topics requiring the value |
| contraction | expected input-to-output ratio and expansion rationale |
| generation | token/revision making stale work rejectable at every boundary |
| sensitivity | path, identity, content, secret, retention, and export policy |
| telemetry | counts, depth/age, service, outputs, drops, and repair state |

Domain manifests conform to this vocabulary:

- filesystem observation and repair descriptors add FSEvent/source-kind and
  authoritative-recovery fields;
- Ghostty action descriptors add callback origin, synchronous handled
  disposition, default-host behavior, and surface/app generation;
- diagnostic streams add evidence-loss accounting and run-validity behavior.

### Reusable Admission Primitive Families

The architecture uses three semantic primitive families rather than one
universal event queue. Exact type names may vary, but their contracts may not:

| Primitive family | Admission/overflow contract | Intended inputs |
| --- | --- | --- |
| latest-value mailbox | one bounded slot per declared key plus at most one pending drain; replacement is the contract and is counted | scrollbar/search/cursor/viewport/current presentation samples |
| coalescing batcher | bounded keys/items/bytes with debounce and maximum latency; values merge by a typed accumulator; overflow creates explicit repair/invalidation rather than silent loss | filesystem paths, Bridge dirty IDs, source invalidations |
| ordered fact channel | exact per-stream order; an accepted item is never silently evicted; lag/backpressure and authoritative recovery are explicit | lifecycle, command completion, notification, health/security, agent-state transitions |

Producer-side admission occurs before allocating one task/message per raw
sample. `Task { await actor.ingest(sample) }` for every callback is not a
mailbox: it merely moves an unbounded task backlog in front of the actor. A
gate schedules at most one drain, and the drain takes a bounded snapshot/batch
or exact fact sequence according to its primitive family. UI samples and exact
facts cannot share one dropping buffer.

## Shared Architecture Decisions

### Semantic Transport

The first cut preserves one generic runtime EventBus and adds exhaustive typed
topic interest before subscriber queue admission. The bus owns transport,
fact-specific replay, fanout, and lag/drop diagnostics. It does not own raw
source observations, terminal presentation samples, domain joins, retry loops,
projection, or UI mutation.

Several typed buses remain a future measured escape if one transport cannot
satisfy independent ordering/recovery needs. They are not an equal option for
the first implementation plan.

### MainActor Last Mile

MainActor owns canonical `@Observable` atoms, AppKit calls, and WebKit delivery.
It accepts typed changed-key mutations and bounded pane-local current-state
updates. It does not own source backlogs, scan scheduling, fleet joins,
canonicalization, Git reads, JSON/regex work over fleets, persistence snapshot
normalization, Bridge package construction, or same-bus derived loops.

Every asynchronous-to-MainActor boundary records separately:

- producer enqueue timestamp;
- MainActor start timestamp;
- synchronous service end;
- operation/domain and generation/revision;
- input and changed-key counts;
- safe run correlation.

An independent responsiveness probe records run-loop starvation. A heartbeat
gap is evidence of starvation, not proof that the immediately preceding named
operation caused it. Stack samples/signposts and work-item spans provide causal
attribution.

### Atoms And Observables

Atoms and observables are canonical state sinks and UI read surfaces. They do
not subscribe to the global bus, own high-rate queues, perform filesystem/Git/
serialization work, or derive and repost product facts. Coordinators/projectors
compute elsewhere and apply typed mutations.

### Safe Authority Defaults

- Local canonical watched roots are authoritative for complete-scan absence.
  Non-local, removable, disconnected, or permission-volatile roots remain
  non-destructive when unavailable until explicit product support exists.
- Git metadata may inform repository identity across paths, but it cannot create
  new watcher authority outside an already user-authorized canonical root.
- Screen-content capture remains a constraints-only future boundary until a
  requester, recipient, user action/consent surface, and result lifetime are
  accepted. Baseline agent or self-pane authority does not include it.
- Terminal-controlled metadata and agent reports are untrusted data and never
  grant command, filesystem, permission, or cross-pane authority.

## Shared Performance Harness Contract

One AgentStudio-owned harness extends the standard isolated debug-observability
runner. It owns the run marker, fixture manifest, build identity, monotonic clock
mapping, stage schema, correlation, final evidence drain, and acceptance report.

The watched-folder child supplies source/topology/Git/Bridge pressure factors.
The terminal child supplies deterministic echo/cursor fixtures, Ghostty host
stages, surface states, and version/host build factors. They do not create
separate runners or definitions of interaction latency.

The terminal child selects `frameLayerPublished`—successful assignment of the
rendered IOSurface to the Ghostty-owned layer—as the mandatory precision
endpoint through an equivalent benchmark-only hook in both vendor builds. It is
not physical scanout. Native PID-targeted proof establishes visible echo/caret/
focus behavior without relabeling automation time as key-to-present latency.

### Scenario Manifest

Every scenario declares:

- initial persisted/runtime state;
- trigger and writers;
- control work and variant work;
- measurement start;
- interaction-ready point;
- pressure-stop point;
- convergence/repair-complete predicate;
- independent expected-state oracle;
- required stage records and evidence-loss policy.

Initial add, cold boot, and steady-state churn are distinct scenarios. Initial
add does not compare a full scan/import with a no-op control: it either uses an
equivalent one-shot scan/import control with watching disabled. Cold boot and
steady state use paired watched/no-watched fixtures where useful work is
otherwise equivalent.

### Evidence Integrity And Correlation

Cross-stage joins use trace/span linkage or ephemeral marker-scoped opaque
tokens unrelated to product IDs. OTLP receives bounded aggregate dimensions and
safe linkage only. Raw paths, pane/surface/root/registration IDs, terminal text,
payloads, prompts, commands, URLs, and errors remain excluded.

The high-rate trace queue is not its own proof of completeness. A bounded,
non-evictable or out-of-band run summary records expected stages, admitted,
recorded, dropped, sequence gaps, final drain result, and run validity. Missing
required stages or failed drain invalidates the run.

### Matrix Shape

The harness defines:

1. a 34-cell mandatory shared core per trial set: ten watched convergence cells
   (`WF-ADD-SCALE-V1`, `WF-COLD-BOOT-V1`, and `WF-HUGE-STEADY-V1`) plus the
   terminal child's 24 vendor/host factorial cells;
2. one-factor and pairwise diagnostic submatrices;
3. separate measurement-probe perturbation controls and profiler/sample runs
   that never substitute for core latency gates.

The watched child owns the exact ten-cell scenario manifests. The terminal
child owns the exact 24-cell build/workload table and reuses
`WF-HUGE-STEADY-V1` in its loaded rows. Dimensions listed elsewhere are
diagnostic coverage requirements, not an implicit full Cartesian product.
Every causal comparison differs only in the factor it claims to isolate and
records the exact app, vendor, compatibility adaptation, measurement probe,
fixture, and configuration identities.

## Requirements / Proof Ownership

| Requirement family | Contract owner | Required proof |
| --- | --- | --- |
| FSEvent loss and topology repair | watched-folder child | deterministic loss/repair plus independent final oracle |
| topology/MainActor/persistence fairness | watched-folder child | work-item spans, responsiveness probe, scaling workload |
| semantic topic transport | parent + watched-folder child | structural policy, queue admission, lag/recovery proof |
| Ghostty tick/action admission | terminal child | state/origin tables, races, sustained producer pressure |
| terminal sample contraction/activity parity | terminal child | sequence oracle, bounded flood, semantic parity |
| secure input/screen boundary | terminal child | owner-state races, denied capture, export canaries |
| combined typing/cursor symptom | shared harness | correlated watched-pressure, input-to-frame-layer-publication tails, and native visible outcomes |

## Threat Model

Assets:

- interaction latency and MainActor availability;
- repository/worktree topology and user-owned metadata;
- terminal/session lifetime, pane attribution, and user intent;
- terminal content, clipboard/secure-input state, filesystem paths, and secrets;
- trustworthy local performance evidence.

Entry points and adversaries:

- local processes producing adversarial FSEvent and `.git` churn;
- unreadable, replaced, symlinked, non-local, or malicious directory trees;
- PTY processes emitting arbitrary output, OSC, titles, URLs, notifications,
  action traffic, and misleading agent reports;
- stale callbacks, registrations, sessions, and queued generations;
- instrumentation overload that hides the measured incident.

Privileged effects include topology removal, watcher registration, pane
orphaning, filesystem/Forge scope, clipboard/secure-input changes, screen reads,
notifications, open-URL requests, and workspace commands. Untrusted input may
request or inform these effects only through the typed owner and authorization
contract named by its child spec.

## Non-Goals

- No implementation sequence, worker allocation, or exact command list.
- No actor-per-pane mandate.
- No claim that static code shape establishes the runtime-dominant hotspot.
- No host-owned VT parser, renderer, or frame loop.
- No claim that layer publication is physical display scanout.
- No new persistence schema requirement; snapshot preparation remains in scope.
- No default-on screen capture or agent authority inferred from terminal data.
- No permanent old/new compatibility pipelines.

## Named Adjacent Spec Boundary

Deep Bridge push/render redesign is adjacent but not hidden inside this pair.
Current source supports a separate future Bridge performance spec if profiling
or the shared stage ledger confirms material cost. That spec must own changed-
ID/mutation-journal capture, off-main delta and final-envelope construction,
one-pass typed serialization, MainActor-only WebKit delivery, stale generation
rejection, normalized/incremental React state, large-list/content
virtualization, and native-to-JavaScript-to-commit correlation. It must not be
implemented from the older audit's ranking alone, and it must remain distinct
from the native `RepoExplorerRowIndex` guardrail.

This contract already forbids global consumers from awaiting Bridge reload/
package/render work and forbids Bridge package construction on MainActor. The
detailed data model and React contract require the separate spec rather than a
planner-local interpretation of those broad prohibitions.

## Planning Gate

The parent, both child specs, and the exhaustive action manifest passed focused
adversarial closure review and are ready for `plan-creation-swarm`. Planning may
operationalize slices and proof gates; it may not redefine action Boolean
semantics, source repair, MainActor ownership, signal planes, security authority,
or evidence validity.

Final capacities, measurement perturbation allowance, and latency ceilings may
be calibrated by the measured plan where their owner is already named. A final
performance-done claim still requires explicit ceilings approved from baseline
distributions. Spec acceptance is not runtime root-cause proof or implementation
proof.
