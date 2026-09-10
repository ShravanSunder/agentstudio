# Bridge Post-DOM Load Performance — Specification

Date: 2026-09-04

Governing requirements:
[2026-09-04-requirements.md](./2026-09-04-requirements.md)

Program realization:
[2026-09-04-program-design.md](./2026-09-04-program-design.md)

## Observable model

PR B measures a load only after its prerequisite runtime is healthy. A valid
initial-load attempt has one browser navigation, one `DOMContentLoaded`
boundary, one requested surface, and one terminal outcome.

```text
readiness preflight
  Vite serves the page
  Swift source server answers its product health check
          │
          ▼
browser navigation
          │
          ▼
DOMContentLoaded ─────────────────────────────────────── T0
          │
          ├─ bootstrap requested and accepted
          ├─ comm worker ready
          ├─ requested File/Review mode admitted
          ├─ source established
          ├─ complete metadata installed
          ├─ initial item selected
          ├─ selected content opened and completed
          ├─ render committed
          └─ requested surface visibly usable ────────── T1

post-DOM load duration = T1 - T0
```

Readiness preflight is a validity condition, not part of the primary duration.
If readiness is lost during the attempt, the attempt fails. It is not silently
excluded or reclassified as an unusually slow successful load.

## Terms

**Ready source runtime** means the composition's asset host can provide the
expected application and its Swift source can accept product operations for
the exact workload before navigation begins. For development this is the Vite
and Swift development-server pair. For packaged proof this is the embedded
asset load and native operation route.

**Initial post-DOM load** means the first File or Review activation in a newly
navigated page, measured from that page's `DOMContentLoaded` timestamp.

**Mode-switch load** means Review-to-File or File-to-Review activation in an
already-open pane, measured from the accepted user/native activation command.

**Usable File paint** means the requested File surface is active and visible,
complete File metadata has established a real selected path, the selected
content is ready and visibly painted, and the destination's navigation and
reading controls are enabled.

**Usable Review paint** means the requested Review surface is active and
visible, complete Review metadata contains real items, selected diff content
is ready and visibly painted, and the destination's navigation and reading
controls are enabled.

**Failed attempt** means an admitted measurement that does not reach its usable
paint terminal state, including timeout, dead source, rejected or stale
authority, transport reset without recovery, repeated-work jam, explicit
unavailability, page/worker failure, or missing stage correlation.

**PR A reliability/correctness failure** means the requested File or Review
does not converge to one exact current usable result: its asset host or Swift
source is unavailable, backend recovery/rebind fails, the foreground pane is
not live, generic transport jams or loses authority, metadata/content is stale,
partial, or wrong, annotations/comments do not deliver correctly, completed
work loops, or no usable terminal is reached. PR B records this as failed
evidence, but PR A owns diagnosis and correction.

**PR B performance miss** means the requested File or Review reaches one exact
current usable-paint success with PR A behavior intact, but its applicable
initial-load or switch distribution exceeds p95 600 ms or p99 1,000 ms. PR B
owns measuring and reducing that elapsed work.

**Run receipt** means one immutable record of a measured run. It identifies its
own source revision, measurement method/version, measurement window, workload,
runtime, attempts, outcomes, and distributions. Results from different source
revisions remain different run receipts even when they are comparable.

**Comparability key** means the dimensions that MUST match before two run
receipts may support a contribution or no-regression claim: viewer or switch
direction, runtime composition, build mode, hardware class, workload/fixture
identity and shape, cache/warmth state, measurement method/version, and
measurement-window policy. Source revision is deliberately not part of this
key because comparison normally evaluates two revisions; each run receipt
retains its own revision.

**Accepted baseline** means one named, inspectable prior run receipt selected
before the comparison is evaluated. A moving aggregate, an unnamed historical
range, or a result chosen after seeing the candidate is not an accepted
baseline.

**Workload cohort** means the attempts inside one run receipt that share its
comparability key and source revision.

## Normative requirements

### R-PDL-001 — Exact primary clock

For an initial File or Review load whose readiness preflight passed, the system
MUST measure elapsed time from the browser's `DOMContentLoaded` timestamp to
the first matching usable File or Review paint.

The clock MUST include all bootstrap, worker, command-admission, source,
metadata, selection, demanded-content, render, and paint work occurring after
`DOMContentLoaded`. It MUST NOT begin at React mount, viewer mount, bootstrap
acceptance, metadata arrival, content readiness, or another later event.

If a measured stage already occurred before `DOMContentLoaded`, its signed
offset MUST remain visible in stage and end-to-end evidence. It contributes
zero post-DOM waiting time but MUST NOT disappear or be rewritten as occurring
at T0.

The primary clock MUST exclude Vite startup, Swift source-server startup, and
document download/parsing before `DOMContentLoaded`.

Basis: U-PDL-001, U-PDL-002.

### R-PDL-002 — Usable-paint terminal

An attempt MUST end successfully only at the first frame where the exact
requested surface satisfies its usable File or Review paint definition.

DOM mount, placeholder chrome, nonempty metadata, selected-content readiness
without visible paint, or paint without enabled controls MUST NOT terminate the
attempt successfully. The terminal observation MUST be correlated to the same
load authority as the start and intermediate stages.

Basis: U-PDL-001, U-PDL-007.

### R-PDL-003 — Initial-load latency targets

For each valid realistic initial File workload cohort and each valid realistic
initial Review workload cohort, post-DOM usable-paint latency MUST be:

- p95 less than or equal to 600 milliseconds; and
- p99 less than or equal to 1,000 milliseconds.

File and Review MUST be reported separately. A combined percentile that allows
one viewer to hide the other is not valid evidence.

Basis: U-PDL-001, U-PDL-005.

### R-PDL-004 — Mode-switch latency targets

For realistic already-open-pane cohorts, Review-to-File and File-to-Review
activation MUST each reach usable destination paint at p95 less than or equal
to 600 milliseconds and p99 less than or equal to 1,000 milliseconds.

The switch clock begins at the accepted activation command, not at destination
mount or content demand. Each direction MUST be reported separately.

Basis: U-PDL-008.

### R-PDL-005 — Complete stage accounting

Every measured initial load MUST expose ordered timestamps or durations for:

1. `DOMContentLoaded`;
2. product bootstrap request;
3. product bootstrap acceptance;
4. comm-worker readiness;
5. requested mode command admission;
6. source establishment;
7. complete metadata installation;
8. initial selection;
9. selected-content open;
10. selected-content completion;
11. render commit; and
12. first usable paint.

When two stages overlap, their timestamps MUST preserve the overlap rather than
forcing the stages into additive serial durations. A stage that precedes T0
MUST retain its negative relative offset. Stage accounting MUST make the
unaccounted interval between adjacent observations visible.

A missing required stage makes the attempt failed measurement evidence. It
MUST NOT be filled from a different attempt, inferred from wall-clock polling,
or silently omitted.

Basis: U-PDL-002, U-PDL-003.

### R-PDL-006 — Honest failure population

Every attempt admitted after a successful readiness preflight MUST produce
exactly one terminal outcome: usable-paint success or classified failure.

Failed attempts MUST remain in the cohort's attempt count and failure count.
Percentiles MUST be calculated only over successful durations and MUST always
be presented with the total attempt count, success count, failure count, and
failure classifications. A cohort with any unresolved jam, missing terminal,
or unexplained correlation gap does not satisfy the reliability prerequisite
for a passing performance claim.

A PR A reliability/correctness failure MUST be retained as failed evidence and
MUST block the affected cohort from a passing PR B claim. Its diagnosis,
recovery, and semantic correction remain PR A work. PR B MUST NOT classify the
failure as a slow success, include it in successful latency percentiles, or
optimize around it.

If the product reaches an exact current usable terminal but required timing
evidence is missing or unjoinable, the attempt is a PR B measurement/proof
failure. It establishes neither a PR A correctness failure nor a PR B latency
pass/miss without separate product evidence.

Retries or backend replacement MAY create a new explicitly identified attempt;
they MUST NOT overwrite the failed attempt that caused recovery.

Basis: U-PDL-003.

### R-PDL-007 — Readiness validity and loss

Before navigation enters a primary performance cohort, evidence MUST establish
that the expected asset host and exact Swift source are ready for product
operations. In development, readiness MUST bind the expected Vite page, port,
Swift source-server process, and workload. In packaged operation, readiness
MUST bind the embedded asset and native operation route. Readiness MUST NOT be
borrowed from a stale process, different port, different app instance, or prior
launch.

If readiness is absent before navigation, no primary latency sample is admitted
and the preflight failure is reported separately. If readiness is lost after
`DOMContentLoaded`, the admitted attempt fails under R-PDL-006.

Basis: U-PDL-003, U-PDL-005.

### R-PDL-008 — End-to-end no-regression guardrail

Every real command-bearing packaged/native initial-load cohort MUST also report
the corresponding Swift-command-to-usable-paint distribution for the same
workload and runtime.

A development-browser cohort with no Swift user-command start MUST explicitly
report that the end-to-end guardrail is not applicable because no such start
exists. It MUST NOT fabricate a timestamp or relabel browser navigation,
readiness preflight, Vite activity, or another browser event as a Swift command.
U-PDL-004 remains required for every path that actually begins with a Swift
open or activation command.

Changes that improve post-DOM latency MUST NOT increase the same-workload
end-to-end p95 or p99 relative to the accepted baseline run receipt with the
same comparability key. Work moved before `DOMContentLoaded` remains visible in
this distribution and cannot count as a post-DOM optimization.

The end-to-end clock and primary clock MUST share the same terminal usable
paint witness so their difference has one interpretation.

Basis: U-PDL-004.

### R-PDL-009 — Realistic and comparable cohorts

Each claimed percentile cohort MUST contain at least 100 attempts. Its run
receipt MUST identify viewer or switch direction, development-server or
packaged runtime composition, build mode, hardware class, workload/fixture
identity and shape, cache/warmth state, measurement method/version,
measurement-window policy and actual window, and the run's source revision.

The workload MUST exercise real Swift-backed source calculation, generic
transport, application metadata consumption, demanded content, and visible
rendering. Review evidence MUST contain many changed files with realistic file
lengths and multi-hunk diffs; File evidence MUST contain realistically sized
source and metadata. Structural, binary, rename, mode, and Unicode/case
examples MUST remain present in semantic coverage even when the timed selected
item is textual.

Failed and missing attempts MUST remain visible. Development and packaged
cohorts MUST be reported separately.

Before a run receipt is used for a contribution or no-regression comparison,
its comparability key MUST exactly match the accepted baseline's key. A key
mismatch invalidates the comparison; it MUST NOT be normalized away, silently
pooled, or described as a measured improvement. Both immutable receipts and
their distinct source revisions remain visible in the comparison.

Basis: U-PDL-005.

### R-PDL-010 — Preserve PR A behavior

Performance changes MUST preserve the reliable generic transport,
application-specific File/Review/annotation contracts, demanded-content
semantics, currentness fences, reset/rebind behavior, foreground liveness, and
comment journeys established by PR A.

An optimization MUST NOT make stale or partial data usable, skip required
metadata, treat unknown content as empty, acknowledge paint before exact
visible evidence, or leave completed demand eligible for repeated work.

If measurement exposes a server/source, recovery/rebind, foreground-liveness,
transport, File/Review delivery, annotation/comment delivery, stale/partial
truth, repeated-work, or missing-terminal failure, that failure belongs to PR A
for correction before the affected PR B cohort can pass. If the exact current
usable result succeeds but exceeds the latency target, the miss belongs to PR B.

Basis: U-PDL-003, U-PDL-007.

### R-PDL-011 — Existing-system optimization boundary

The first realization MUST improve measured work through existing owners and
existing delivery paths. It MUST NOT add a cache, watcher, queue, worker,
scheduler, service, persistence layer, transport route, or new product data
protocol, and MUST NOT redesign File View, Review View, annotations, comments,
or viewer chrome.

If evidence proves that the target cannot be met inside those boundaries, the
implementation MUST stop at a documented design break rather than silently
introduce a prohibited system.

PR B MAY instrument or optimize work inside an existing bootstrap, worker,
transport, consumer, content, or render owner only when its PR A observable
data, authority, recovery, delivery, and failure semantics remain unchanged.
A required correctness-contract change is PR A work, not an optimization
licensed by this requirement.

Basis: U-PDL-006, U-PDL-007.

### R-PDL-012 — Optimization follows measured contribution

Each delivered optimization MUST name the stage interval it reduces and MUST
show that interval before and after the change using the candidate run receipt
and one accepted baseline run receipt with the same comparability key.

An optimization that changes no measured stage, merely relabels a boundary,
drops failures, weakens usable-paint criteria, or shifts work outside the
primary clock MUST NOT count toward R-PDL-003 or R-PDL-004.

Basis: U-PDL-002, U-PDL-004, U-PDL-006.

## Observable journeys

### Initial Review after both servers are ready

```text
operator proves Vite and exact Swift source ready
  -> browser navigates to Review
  -> DOMContentLoaded starts the primary attempt
  -> bootstrap and comm worker become ready
  -> Review source and complete metadata install
  -> a real Review item becomes selected
  -> demanded diff content completes
  -> the selected diff and controls visibly paint
  -> one successful Review duration and complete stage record exist
```

If any post-DOM stage jams or the source dies, the attempt ends as a classified
failure and remains in the cohort.

### Initial File after both servers are ready

The same journey ends only when a real selected path and demanded file content
are visible with usable File controls. Review metadata or placeholder content
cannot satisfy the File terminal.

### File and Review mode switches

```text
source mode is usable
  -> reviewer or native command activates destination mode
  -> destination command is admitted
  -> destination source/metadata/selection/content become current
  -> destination reaches exact usable paint
```

The source surface may remain retained according to PR A. The destination
cannot claim success merely because it was previously mounted.

### Server fails during a timed load

The admitted attempt fails with its last completed stage and source-loss
classification. PR A owns recovery and correction. PR B retains the failed
attempt but does not tune around it; recovery does not erase or rewrite the
failed attempt. A later attempt receives a new identity.

### A correct load misses the latency target

The exact requested surface reaches current metadata, selection, demanded
content, visible paint, and usable controls with no PR A failure. Its successful
duration remains in the File, Review, or switch distribution. When that
distribution exceeds p95 600 ms or p99 1,000 ms, PR B owns stage attribution
and optimization inside the existing-owner boundary.

## Observable reporting contract

| Report field | Required meaning |
| --- | --- |
| run identity | immutable receipt name, source revision, measurement method/version, actual window, and attempt population |
| comparability key | viewer/direction, runtime composition, build mode, hardware class, workload/fixture identity and shape, cache/warmth state, measurement method/version, and window policy |
| accepted baseline | one named, inspectable prior run receipt selected before evaluation, with an exactly matching comparability key and its own source revision |
| population | total, successful, failed, and classified-failure counts |
| primary distribution | p50, p95, and p99 from `DOMContentLoaded` to usable paint |
| switch distribution | p50, p95, and p99 from accepted activation to usable destination paint |
| end-to-end guardrail | for real command-bearing packaged/native runs, p50, p95, and p99 from Swift command to the same usable paint; for development-browser runs without that start, explicit not-applicable reason and no substitute timestamp |
| stage distribution | p50, p95, and p99 for each required stage timestamp/interval |
| accounting gap | time not assigned between required observations, never silently absorbed |
| comparison | candidate and accepted-baseline receipts, exact key match, distinct revisions, and before/after contribution for each optimization |

## Requirement-to-proof coverage

| Need | Problem/outcome | Requirement | Observable contract | Proof modality |
| --- | --- | --- | --- | --- |
| U-PDL-001 | initial viewers miss a predictable useful-state budget | R-PDL-001, R-PDL-002, R-PDL-003 | exact post-DOM clock and usable terminal | performance measurement plus visible-state inspection |
| U-PDL-002 | aggregate timing cannot locate delay | R-PDL-005, R-PDL-012 | complete ordered stage record and before/after attribution | trace and metric observation |
| U-PDL-003 | jams can disappear from percentiles | R-PDL-006, R-PDL-007, R-PDL-010 | one terminal per admitted attempt; failures retained | real-runtime failure/recovery evidence and cohort inspection |
| U-PDL-004 | a later clock can hide earlier regressions | R-PDL-008, R-PDL-012 | paired Swift-command and post-DOM distributions for every real command-bearing path; explicit not-applicable development-browser result when no Swift command exists | joined native trace/metric comparison without fabricated browser substitute |
| U-PDL-005 | tiny fixtures and mismatched runs understate or misattribute real work | R-PDL-009 | real Swift-backed rich cohorts plus immutable comparable run receipts | development and packaged performance evidence with exact comparison-key validation |
| U-PDL-006 | optimization can create new lifecycle systems | R-PDL-011, R-PDL-012 | existing-owner change with measured contribution | architecture inspection plus before/after evidence |
| U-PDL-007 | speed can weaken currentness or comments | R-PDL-002, R-PDL-010, R-PDL-011 | exact current usable paint with PR A semantics intact | transport/annotation/comment regression and real-runtime proof |
| U-PDL-008 | context switches can repeat cold work | R-PDL-004 | direction-specific switch percentiles | real-runtime switch distributions |

## Compatibility and negative space

- Existing telemetry names and stage facts may be extended or correlated, but
  no telemetry result becomes product authority.
- Missing telemetry must fail performance evidence, not product loading.
- Recording or classifying a PR A failure in a PR B receipt transfers no
  recovery or correctness ownership to PR B.
- PR B does not promise that an unready or currently rebuilding development
  server meets the post-DOM latency target.
- PR B does not define a latency target for Vite compilation or Swift server
  compilation/startup. A real command-bearing packaged/native path exposes
  native and WebView startup through the separate end-to-end guardrail. A
  development-browser path without a Swift command reports that guardrail as
  not applicable and does not invent a substitute start.
- Source revision identifies an immutable run receipt but does not belong to
  the cross-revision comparability key. Two receipts with different revisions
  may be compared only when every comparability-key dimension matches and one
  was named as the accepted baseline before evaluation.
- Mismatched run receipts may remain useful diagnostic evidence, but they
  cannot prove stage contribution, improvement, or no regression.
- PR B does not permit a second browser client to share one single-pane
  development authority unless PR A separately promises that topology.
- Security, privacy, accessibility, offline behavior, and data semantics remain
  those of PR A; performance instrumentation must not export raw paths, file
  contents, diffs, comments, credentials, or source identifiers.
