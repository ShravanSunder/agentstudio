# CI Reliability — Specification

What must be observably true for CI to be a trustworthy gate. Needs and boundary are in the
[Requirements](2026-09-17-ci-reliability-requirements.md) (`U`, `E`, `H` identifiers resolve there). Internal
structure is in the [Program Design](2026-09-17-ci-reliability-program-design.md).

## The model in one view

A test result should depend on two things only: the code under test and the test. Today it also depends on the
machine.

```text
                 what decides pass or fail

   TODAY                                  REQUIRED
   ─────                                  ────────
   the change under test                  the change under test
   the test                               the test
   how many cores the runner has          ─
   how many other tests are in flight     ─
   how fast a scheduler turn is           ─
   whether a cold build fit a budget      ─
```

Three kinds of clock can appear in a test. Only one may decide a result, and it never decides a result for a working
system.

| Clock role | Meaning | Status |
| --- | --- | --- |
| Correctness budget | "passes only if X happens within N" — N in seconds, polls, or scheduler turns | Forbidden (R3) |
| Subject | Time is the behavior under test (debounce, cadence, backoff, retention) | Allowed only through a clock the test controls (R5) |
| Hang bound | "if X never happens, fail instead of hanging" | Allowed; one per test, owned by the runner (R4) |

## Who relies on what

The reliability system is one opaque box. These are the surfaces its consumers touch.

```text
   implementing agent ──── writes a test ─────────► ┌───────────────────────┐
        │                  (C2 waiting forms)       │                       │
        │                                           │   test + CI system    │
        ├── runs lint ──── (C4 lint verdict) ─────► │                       │
        │                                           │   (opaque here)       │
        └── reads the standard (C6) ◄────────────── │                       │
                                                    │                       │
   owner / reviewer ◄──── CI verdict + lane ─────── │                       │
   orchestrating agent     report (C1)              │                       │
                                                    │                       │
   production shutdown ─── awaits quiescence ─────► │                       │
   and tests               (C3)                     │                       │
                                                    │                       │
   dev viewer (browser) ── session handoff (C5) ──► │                       │
                                                    └───────────────────────┘

   not consumers: end users of the shipped app; the IPC surface;
   post-merge benchmark lanes; release signing.
```

## Outcomes

| ID | Outcome | Observable success |
| --- | --- | --- |
| O1 | A CI verdict reflects the change, not the machine | The acceptance measure in R18 holds |
| O2 | Tests wait on completion, never on elapsed time | No test contains a forbidden wait (R3), enforced by the lint gate (R11) |
| O3 | Production can say "I am done" on the paths tests and shutdown need | Each listed owner offers quiescence with the semantics of C3 (R6, R7) |
| O4 | A written, enforced standard exists and nothing contradicts it | C6 exists and is routed; R12 audit is clean |
| O5 | Every diagnosed failure family is resolved at its cause | The family table under R9 is fully dispositioned |
| O6 | Workarounds do not outlive their cause | R13 holds for every pin and hand-maintained list |

## Normative requirements

### Test execution

**R1 — Bounded concurrency.** While a Swift test lane runs, the number of test cases executing concurrently inside
one test process MUST be bounded by a value derived from the runner's CPU count. *Basis: U1, U3, E3.*
*Fails if:* a lane log shows test cases in flight far beyond that bound (E3 observed about 4,900 on 3 CPUs).

**R2 — Lanes report their own load.** Each Swift test lane MUST print, in its output, the runner's CPU count and
memory, the concurrency bound in effect, the number of test processes it runs at once, and the lane's CPU
utilization (CPU time divided by wall time times CPU count). *Basis: U3.* *Fails if:* a reader cannot tell from a lane
log whether the runner was saturated, blocked, or idle.

### How a test may wait

**R3 — No correctness budgets.** A test MUST NOT decide pass or fail by an elapsed-time budget, a poll count, or a
scheduler-turn count. A wait in a test MUST complete because a named event, a completion signal, an observed state
change, or a quiescence signal occurred. *Basis: U4, U5.* *Fails if:* a wait can expire while the awaited work is
correct and still in flight.

**R4 — One hang bound, never tuned.** The only elapsed-time bound permitted in a test is the runner-owned hang bound:
the test framework's time limit on the test. A lane may additionally bound the whole lane against a hung process; that
is also a hang bound and follows the same rule. If a test's hang bound expires, the failure MUST identify what was being awaited. A hang bound MUST NOT be raised to make a correct but
slow test pass; such a test indicates a violation of R1, R3, or R8. *Basis: U4.*

**R5 — Time as subject uses a controlled clock.** Where the behavior under test depends on time, the test MUST drive
that time through a clock it controls and MUST NOT wait in real time. If a component under test reads more than one
clock, every clock that can affect the asserted outcome MUST be controllable by the test. *Basis: U4, E6 (tests that
inject a clock and never advance it; a second real clock inside the same component).*

**R6 — Proving a negative.** When a test must show that something does not happen, it MUST first await quiescence
(C3) of every component that could cause it, and then assert once, synchronously. *Basis: U5, U6.* *Fails if:* a test
treats "did not happen during a budget" as "does not happen".

### What production must offer

**R7 — Quiescence is available where waiting is needed.** A production component that accepts asynchronous work whose
completion tests or shutdown must await MUST offer quiescence with the semantics of C3. It MUST be a production
contract, usable by shutdown, and MUST NOT be a test-only hook or compiled only in debug builds. *Basis: U6; repository
rule against new `#if DEBUG` test hooks.*

**R8 — No blocking on the cooperative pool.** Test code, and production code reachable from tests, MUST NOT block a
Swift cooperative-pool thread on process exit, a semaphore, a lock held across long work, or synchronous I/O.
*Basis: U1, U7, E3; existing `CLAUDE.md` Swift 6.2 rule.* *Fails if:* a blocking wait can occupy a pool thread that the
work it waits for needs.

**R9 — Families are fixed at their cause.** Each failure family below MUST be resolved at its diagnosed cause. None
may be resolved by retry, skip, quarantine, a raised budget, or removing an assertion without a replacement that
states the invariant at least as strongly. *Basis: U3, U7; `CLAUDE.md` proof-gate rule.*

| Family | Diagnosed cause | Required observable correction |
| --- | --- | --- |
| File source context leak | Production: an interrupted open kept its context installed | If an open is interrupted after its context is installed, then the source releases that context; a deterministic test reproduces the interruption |
| Hidden pane admits a frame (most frequent) | Test asserts a total that includes protocol acknowledgements | The test asserts that pane, file, and review product-frame counts are unchanged while hidden; protocol acknowledgements remain free to flow |
| Cache coordinator convergence; coalesced burst | Poll budget expired while work was in flight across five buffers | The tests await pipeline quiescence (C3), then assert |
| Launch-restore surface creation; refresh admission comparison | Poll budget | The tests await the owner's completion signal |
| Repo explorer capture count | Test samples its baseline from a value written mid-capture | The baseline is taken after the capture's completion signal |
| Visible-tier cadence | Time is the subject but the injected clock is never advanced; a second real clock exists | R5 holds for these tests |
| Exact-item FSEvents stream | One sentinel event treated as "stream drained" | The test awaits the stream's existing activity fence |
| Pane-agent helper exit | Blocking wait on a pool thread that the in-process server needs | R8 holds |
| Review replay (`sessionAlreadyOpen`) | Session handoff race after a stream has ended | R16 holds |
| Worktree-data integration (HTTP 409) | The test opens a second session while its first is still open, which the host does not support | The test closes its first surface before opening the second; the refusal it used to hit is typed (C5) |
| BridgeWeb backpressure E2E | Dependency optimizer cold inside the measured window on every attempt | R14 holds |
| BridgeWeb share-shelf timeouts | Unbounded, uncaught animation await | R15 holds |
| BridgeWeb annotation E2E `source.refresh` | Not yet diagnosed: after the root annotation is created the File surface did not report a committed refresh for 120 s, against a norm near 1 s, while the Review sibling passed | Diagnosed before it is fixed (H5). Until then the journey reports which commands did arrive when this wait fails, and its derived waiters are abandoned rather than orphaned when their antecedent fails |
| Ghostty header not found | Vendor artifact availability in CI | The lane fails before tests with a message naming the missing vendor input, or the input is always present |

### Standard, enforcement, and hygiene

**R10 — One written standard.** The repository MUST contain one test-waiting and CI-reliability standard, reachable
from the root agent instruction file's routing table, stating the permitted waiting forms (C2), the forbidden forms,
the quiescence contract (C3), the hang-bound rule, the blocking rule, and the workaround rule (R13). *Basis: U2.*

**R11 — The standard is enforced mechanically.** The lint gate MUST fail when Swift test code contains a polling wait:
a loop that repeats around a scheduler yield, a sleep, or a clock deadline until a condition holds, or a parameter
that budgets such a loop. At completion there is no allowlist. While existing polling waits are being converted, the
gate MAY carry a baseline of files that still contain them, provided the baseline can only shrink: a file outside it
that polls fails the gate, and a file inside it that no longer polls fails the gate until it is removed. The work is
not complete (R18) while the baseline is non-empty. *Basis: U2, U5; hard-cutover rule.* *Fails if:* a new polling
helper can be added and the gate stays green.

**R12 — Nothing contradicts the standard.** No agent instruction file, guide, workflow, or task configuration may
instruct or permit a forbidden pattern, recommend raising a budget or rerunning as a response to a failure, or
describe tooling behavior that the tooling does not have. *Basis: U9.*

**R13 — Workarounds and hand-kept lists are checkable.** A version pin or note that exists for a workaround MUST state
a condition under which it is removed, and MUST be removed once that condition is met. A hand-maintained list that
test correctness depends on (such as the set of suites that need process isolation) MUST be verified by a gate, so
that a member cannot silently fall out. *Basis: U7, E9, E6 (a suite absent from the isolation list beside its listed
sibling).*

### BridgeWeb

**R14 — Cold start is outside the measured window.** A BridgeWeb E2E journey's bounded steps MUST NOT include
dependency-optimizer cold start, and a retry MUST NOT repeat a cost that made the first attempt fail. Each live Vite
server MUST still own its cache directory. *Basis: U1, E8; `docs/guides/agent_resources.md` cache-isolation rule.*

**R15 — BridgeWeb waits are condition-driven and declared.** A BridgeWeb test wait MUST complete because an
application event or a DOM condition occurred. Its time bound is a hang bound: declared once in shared configuration,
never an undeclared library default, and never tuned per test to obtain a pass. An awaited animation MUST be driven to
completion by the test or have its cancellation handled; it MUST NOT be awaited unbounded or uncaught. *Basis: U1, U4,
E8.* See H4.

**R16 — Same-viewer session handoff is deterministic.** When a successor document of the same viewer requests an
initial session while its predecessor's session has not finished retiring, the development host MUST grant the
successor a session without the successor retrying and without any time-based grace. If a different viewer requests a
session while a live viewer holds it, then the host MUST refuse with a typed "in use" result, and the client MUST
present that result distinctly from a transport failure. A client that requests a second session while its own first
session is still open and not closing is refused the same way; that shape is not supported. *Basis: U1, E8, H2.*

### Finish line and delivery

**R17 — Packaging.** The reliability changes MUST land separately from and ahead of PR #350, as two stacked pull
requests: the first carries everything except the bulk conversion of remaining polling waits and is sufficient to
unblock PR #350; the second carries that conversion, adds the serialized E2E lane to CI, and ends with an empty
baseline. Each pull request merges under the repository's existing pull-request gate. In addition the first merges
only after "CI / Test" has passed on its head twice in a row on the first attempt; PR #350 merges after it.
*Basis: U8 and the owner's decisions of 2026-09-17.*

**R18 — Acceptance measure.** The work is complete when "CI / Test" completes green on the first attempt, with no job
rerun, for ten consecutive runs spanning `main` and pull requests that do not themselves change test infrastructure,
the lane reports (R2) for those runs show the concurrency bound in effect, and the polling baseline (R11) is empty.
Deliberately triggered runs count. A run that fails resets the count and is diagnosed, never rerun to obtain green;
a cancelled run neither counts nor resets. Lane reports are collected from every run from the first pull request
onward. *Basis: U1, H1.*

## Observable contracts

### C1 — CI lane report

Consumer: owner, reviewers, orchestrating agents. Each Swift lane's log contains, before its tests run, the runner CPU
count, memory, concurrency bound, and process count; and after they run, wall time, CPU time, and utilization. A
missing vendor input is reported before any test starts, by name. Undefined: the exact text format, beyond being
greppable by stable labels.

### C2 — The forms a test may use to wait

Consumer: anyone writing a Swift test.

| Situation | Permitted form | Forbidden |
| --- | --- | --- |
| State changes and is observable | Await the observed change until a predicate holds | Re-reading the value in a loop |
| A component or test double knows when something happened | Await its event or completion signal | Polling a counter it keeps |
| Delivery on a stream or the bus | Subscribe before the stimulus, then await the specific element | Polling subscriber counts or received arrays |
| Work finishes but announces nothing | Await the owner's quiescence (C3) | Yield-and-hope |
| Something must not happen | Await quiescence, then assert once | "Did not happen in N turns/seconds" |
| Time is the behavior | Advance a controlled clock | Waiting in real time |
| None of the above fits | The production owner is missing a signal; add it under R7 | Any poll |

### C3 — Quiescence

Consumer: tests and production shutdown.

- **Meaning.** Awaiting quiescence on a component completes only when every unit of work the component accepted
  before the await began has been finished and handed to the next stage, including work buffered for coalescing,
  debounce, or a later tick.
- **Applied, not delivered.** When quiescence is reported, every effect of that work is visible in the state the
  component publishes. "The consumer has been handed the item" is not quiescence.
- **Work accepted during the await.** Quiescence MUST NOT complete while such work is unfinished if it was caused by
  the work being awaited. Whether unrelated new work extends the await is left to each owner and documented by it.
- **Pipelines.** Quiescence of a pipeline holds only when all of its stages are quiescent at the same time; a stage
  finishing can hand work to a stage that was already quiescent.
- **Held work versus a standing schedule.** Work already accepted and merely held for a coalescing, debounce, or tick
  window is unfinished work: the component is not quiescent. A standing schedule that will generate work in the future
  (a periodic refresh waiting on its next deadline) is not accepted work and does not prevent quiescence.
- **Clocks.** A test that controls the component's clock advances it and then awaits quiescence. Awaiting quiescence
  in a test never completes by letting real time pass. A component whose held work is released by a clock therefore
  makes that clock controllable by the test (R5).
- **Dropped delivery.** Quiescence covers work a component accepted. An envelope that a bounded, lossy subscription
  discarded was never accepted, so quiescence says nothing about it. A test whose outcome depends on delivery across
  such a subscription asserts that the subscription dropped nothing.
- **Shutdown and cancellation.** If the component shuts down, then pending awaits complete rather than hang. If the
  awaiting task is cancelled, then the await ends promptly and leaves no stored waiter behind.
- **Cost.** With no one awaiting, quiescence adds no work to the hot path beyond bookkeeping the component already does.
- **Not promised.** That no future work will arrive; ordering across independent pipelines; a whole-application idle
  signal; any exposure over IPC; suitability for measuring performance.

### C4 — Lint verdict for polling waits

Consumer: implementing agents, CI. Input: Swift sources under `Tests/`. On violation the gate fails and names the file
and line, a stable rule identifier, and the standard's location. It runs wherever the existing architecture lint runs
(`mise run lint`, and therefore `mise run test` and CI). Undefined: detection of polling disguised beyond a loop around
a yield, sleep, or deadline; reviewers still own that.

### C5 — Development-host session handoff

Consumer: the BridgeWeb development client.

| Situation | Result |
| --- | --- |
| No live session | Session granted |
| Same viewer's successor once the predecessor's stream has ended, even if the host has not finished retiring it | Session granted; predecessor retired; no client retry, no timed grace |
| Same viewer's successor after the predecessor vanished without closing (reload, crash) | Session granted on the same terms |
| Same client asks for a second session while its first is still live and not closing | Typed "in use" refusal. Not a supported shape; a client closes its first session before opening another |
| Different viewer while a live viewer holds the session | Typed "in use" refusal; client shows "open elsewhere" |
| Any refusal | The response says which case applied; a client never collapses it into an untyped error |
| Backend unreachable | Transport failure, distinct from "in use" |

Undefined: how a viewer proves it is the same viewer; chosen in Program Design. Out of scope: the shipped app's pane
session path, which does not use this host.

### C6 — Where the standard lives

Consumer: every agent and contributor. One document under `docs/architecture/`, linked from the root instruction
file's "Open The Right Doc" table with the mistake it prevents, and from `BridgeWeb/AGENTS.md` for R14–R15. The root
file's "No Wall-Clock Tests" section names scheduler-turn loops explicitly and points to the standard rather than
restating it.

## Cross-cutting obligations

| Quality | Obligation |
| --- | --- |
| Reliability | R1–R9, R14–R16, R18 |
| Performance | Quiescence adds no hot-path cost without an awaiter (C3). Bounded concurrency MUST NOT lengthen a lane's wall time by more than the lane report can explain; regressions are visible through R2 |
| Observability | R2, C1. No new telemetry export; lane reports are log lines |
| Security and privacy | Same-viewer proof in C5 MUST NOT let a different local process take over a session it could not already access; development host only |
| Compatibility | Hard cutover: at completion no polling helper remains beside the new forms. No dual toolchain pin: the release and benchmark workflows move with CI in the first pull request, by the owner's decision. A tagged release cannot be withdrawn by reverting a workflow, so the first release built on the new toolchain follows the repository's existing release smoke before it is relied on |
| Accessibility, data lifecycle, compliance | Not applicable: no user-facing surface or stored data changes |

## Proof obligations

| ID | Proves | Evidence class |
| --- | --- | --- |
| V1 | R1, R2 | CI log observation: lane report fields present; in-flight count within the bound |
| V2 | R3, R11 | Automated: the lint gate fails on a seeded polling wait and passes on the tree; state inspection: zero polling helpers remain |
| V3 | R4 | Automated: a deliberately hung wait fails with a message naming what was awaited |
| V4 | R5 | Automated: time-subject tests pass with the controlled clock and never read real time |
| V5 | R6, R7, C3 | Automated behavior at each owner: quiescence does not complete while accepted work is buffered or in flight; completes after effects are published; completes on shutdown; cancellation leaves no waiter. Integration: pipeline quiescence across all stages |
| V6 | R8 | Static inspection plus the lane report's utilization; automated test for the pane-agent helper |
| V7 | R9 | Per family: the corrected test passes, and where a deterministic reproduction exists it fails before the fix |
| V8 | R10, R12, R13 | Document inspection against an audit checklist; automated gate for list membership |
| V9 | R14, R15 | CI log observation: no optimizer cold start inside a bounded journey step; automated browser tests |
| V10 | R16, C5 | Automated integration through the real development server for each row of C5 |
| V11 | R17, R18 | Release and runtime evidence: the PR order; ten consecutive first-attempt green runs with their lane reports; an empty baseline |

## Requirement coverage

| Need | Outcome | Requirements | Contracts | Proof |
| --- | --- | --- | --- | --- |
| U1 | O1 | R1, R8, R14, R15, R16, R18 | C1, C5 | V1, V6, V9, V10, V11 |
| U2 | O4 | R10, R11 | C4, C6 | V2, V8 |
| U3 | O1, O5 | R1, R2, R9 | C1 | V1, V7 |
| U4 | O2 | R3, R4, R5, R15 | C2 | V2, V3, V4, V9 |
| U5 | O2 | R3, R6, R11 | C2, C4 | V2, V5 |
| U6 | O3 | R6, R7 | C3 | V5 |
| U7 | O5, O6 | R8, R9, R13 | — | V6, V7, V8 |
| U8 | — | R17 | — | V11 |
| U9 | O4 | R12, R13 | C6 | V8 |

## Open decisions

| ID | Decision | Owner | Effect if unresolved |
| --- | --- | --- | --- |
| H3 | Whether the single content-hash mismatch is a product defect | Repository owner, after investigation | Not addressed here; tracked separately |
| H5 | Why the File surface reported no committed refresh in the annotation E2E | Whoever diagnoses it; the owner if it proves to be product behavior | That one family stays open; it does not block the first pull request |
| H4 | Whether BridgeWeb should go beyond R15 and remove DOM-condition polling as Swift does | Repository owner | R15 stands: condition-driven waits with one declared hang bound |
