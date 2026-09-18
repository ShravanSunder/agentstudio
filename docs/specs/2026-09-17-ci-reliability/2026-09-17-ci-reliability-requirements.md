# CI Reliability — Requirements

Why this work exists, for whom, and within what boundary. What must be observably true lives in the
[Specification](2026-09-17-ci-reliability.md); how it is built lives in the
[Program Design](2026-09-17-ci-reliability-program-design.md).

```text
Requirements (this file)  ->  Specification  ->  Program Design
```

## The problem in one picture

```text
  a change is pushed
        │
        ▼
  CI runs Swift lanes + BridgeWeb lanes
        │
        ├── red, and the change is wrong        (the signal we want)
        ├── red, and the change is fine         (happens most weeks; evidence E1)
        └── green only after "rerun failed jobs" (hides the defect; E1, E2)

  so today a red X does not mean "your change is broken", and a green
  check does not mean "this commit passes". People and agents respond by
  rerunning, raising a number, or patching one test. The flakes return (E7).
```

## Who is affected

| Class | Their job | What unreliable CI costs them |
| --- | --- | --- |
| Owner / maintainer | Decide whether a PR may merge and a release may be cut | Cannot trust red or green; merges stall on unrelated failures (PR #350, an icon-only change, blocked by three unrelated flakes on one commit) |
| Implementing agents | Land a scoped change with proof | Spend the task diagnosing failures they did not cause; learn to rerun rather than fix |
| Orchestrating / reviewing agents | Judge readiness from CI and local gates | Must re-derive "is this failure mine?" on every PR; no written standard to hold work to |
| Future test authors (human or agent) | Write a test for asynchronous behavior | No sanctioned way to wait; 123 private polling helpers to copy from (E4) |

## User requirements

Authority state is the producer's: `authorized` rows are the owner's own statements in the 2026-09-17 session and
are the only rows a normative requirement may rest on. Priority was assigned by the owner unless marked.

| ID | Need or outcome | Why it matters | Owner's words (2026-09-17) | Authority | Priority |
| --- | --- | --- | --- | --- | --- |
| U1 | CI for the Swift lanes and the BridgeWeb lanes is reliable | It is the merge and release gate | "i want a very important goal the ci to be reliable its been so flakey for last 2 weeks for swift and bridge steps" | authorized | P0 |
| U2 | There is a written standard that other agents follow | Flakes were fixed one at a time before (#327, five flakes, 2026-09-05) and returned | "we need to establish standards that other agents will follow" | authorized | P0 |
| U3 | The causes are actually analyzed, not patched around | Same reason as U2 | "really analyze why"; "what the best way to holistically to solve this" | authorized | P0 |
| U4 | Tests do not decide pass or fail by elapsed time, in any unit | A time budget passes on a fast machine and fails on a loaded one | "i didnt want wall clock based tests this is why we do not have wall clocks" | authorized | P0 |
| U5 | Counting scheduler turns is treated as a wall clock too | "Nothing happened in N turns" is a time budget in a load-dependent unit | "this is just another way of wall clock ... i dont like that" | authorized | P0 |
| U6 | Production code may expose quiescence seams so tests can wait on real completion | It is the alternative to polling | "yes to quiescence seams" | authorized | P1 |
| U7 | Accumulated bad patterns are cleaned up, not only the currently failing tests | Latent flakes surface one at a time otherwise | "lets clean up a bunch of bad stuff"; "sounds like a multi pronged fix" | authorized | P1 |
| U8 | The reliability work ships as its own pull request, ahead of PR #350, and #350 then merges | Keeps an icon PR from carrying Bridge and test-infrastructure changes | Selected "Separate reliability PR first"; "lets get this thing merged" | authorized | P1 |
| U9 | Agent instructions and tooling configuration are audited for anything that teaches or hard-codes these patterns | The standard is worthless if the existing instructions contradict it | "get subagent to parse all the agents.md or mise for weird stuff too with regards to this" | authorized | P1 |

## Owner-set limits on how the work is done

These constrain delivery. They are not product behavior.

- The orchestrator specifies the fixes; implementation is delegated to subagents after the design is clean
  ("you specify the fixes please"; "get subagents to work on it after clean up design"). Implementers run on Claude
  Opus at low effort or Haiku ("make sure you use opus low or haiku").
- Repository rules in `CLAUDE.md` bind this work and are not reopened here: a proof gate is never deleted, weakened, or
  disabled to obtain a pass; test topology has one owner (`mise run test:*` and `scripts/run-swift-test-task.sh`); no
  new `#if DEBUG` test hooks in production files; no `Task.sleep` in test bodies; hard cutover with no dual paths;
  adding an atom, store, event type, or coordinator responsibility requires asking the owner.
- Toolchain fact confirmed by the owner: "we are in zig 16 now for new zmx and new ghostty."

## Goal boundary

| Field | Boundary |
| --- | --- |
| Primary goal | A red CI result means the pushed change is wrong; a green result means the commit passes, without reruns |
| Affected classes | The four classes above |
| Existing foundation to reuse | The `mise run test:*` lane topology; Swift Testing; event-driven test doubles already built on stored continuations (380 declarations across 122 test files, E4); production completion signals that already exist (`RemoteReferenceRefreshActor.waitUntilIdle()`, `BackgroundFactApplyGovernor.Acknowledgement`, FSEvents activity fence, E6); `Tools/AgentStudioArchitectureLint` |
| What is actually missing | A bound on concurrent test execution (E3); a sanctioned non-polling way to wait (E4); completion signals on the production paths tests need (E6); a standard and its enforcement (U2); correction of assertions and instructions that are simply wrong (E5, E8, U9) |
| May change | Test code and test support; CI workflows and mise test tasks; the pinned Xcode version; production code where it fixes a defect found here or exposes a completion signal (U6); agent instruction files and architecture docs; BridgeWeb test harnesses and the development host's session handoff |
| Protected | Shipped product behavior unrelated to a defect found here; proof strength of every existing test; the vendored Ghostty and zmx sources; release identity and signing; per-server Vite cache isolation (`docs/guides/agent_resources.md`, "BridgeWeb Fast UI Loop") |
| Non-goals | Quarantining, skipping, or retrying tests to obtain green; raising time or turn budgets as a fix; a larger CI runner as the fix; rewriting tests that do not wait on asynchronous state; new test frameworks; performance benchmarking of the app (post-merge benchmark lanes are out of scope); fixing PR #350's own content |
| Acceptable complexity | One shared set of waiting primitives and one quiescence contract. A second waiting convention, a test-only production hook, or a per-suite bespoke mechanism reopens scope. Adopted by the owner on 2026-09-17 with one exception: existing polling helpers and the new primitives may coexist between the two stacked pull requests, and only then; the empty lint baseline marks the end of that window |

## Evidence

Observational. Each row says what was seen and where to inspect it; none of them authorizes behavior by itself.
Reports are under [`docs/wip/2026-09-17-ci-reliability-evidence/`](../../wip/2026-09-17-ci-reliability-evidence/).

| ID | Observation | Source |
| --- | --- | --- |
| E1 | In the last 40 "CI / Test" runs, 31 failed jobs across Swift fast, large, and WebKit lanes and three BridgeWeb jobs; the same failures recur across unrelated branches | Work trail checkpoint 2; `lane-bridgeweb-flakes.md` §D corrects two rows that were green |
| E2 | PR #350 (three-file icon change): attempt 1 failed two fast-lane suites; attempt 2 of the same commit passed those and failed a third suite in the large lane; the WebKit lane never ran | CI run 34964090273, attempts 1 and 2 |
| E3 | Fast lane: 5,218 test results whose durations sum to 183,718 s inside a 125 s run; median 44.6 s, p90 52.6 s. CI pins Xcode 26.3, whose Swift Testing has no parallelism cap; Xcode 26.6 has one, off unless explicitly set, and is the runner image default. Runner is 3 vCPU / 7 GB; the owner's machine is 16 cores / 64 GB | `lane-swift-runner-starvation.md`; reproduced from the raw log; binary inspection of both Xcode versions |
| E4 | 123 polling wait helpers and 678 call sites plus 162 inline loops; 87 helpers budget by `Task.yield()` turn count with defaults from 50 to 300,000; two shared helpers cover 225 sites with a dual turn-and-time budget whose own documentation says neither budget is reliable | `polling-wait-survey.md` |
| E5 | The most frequent Swift failure asserts a total frame sequence that legitimately includes protocol acknowledgements; product frame counts were unchanged in the failing run | `lane-webkit-hosted-panes.md` |
| E6 | Nine further Swift failures: four poll-budget, three ordering assumptions, two environment, none a product defect. Seven production owners need an awaitable completion signal; four already have one that the caller discards or that misses the tested path | `lane-swift-flake-families.md` |
| E7 | Five Swift flakes were fixed individually in #327 (merged 2026-09-05); the class returned within two weeks | `gh pr view 327` |
| E8 | BridgeWeb: the dependency optimizer runs cold in every E2E fixture so the single retry cannot help; one unbounded animation await causes two 60 s timeouts; a development-host session handoff race returns HTTP 409 to a same-viewer successor that an existing test expects to succeed | `lane-bridgeweb-backpressure-e2e.md`, `lane-bridgeweb-flakes.md` |
| E9 | The Xcode 26.3 pin is a workaround for zig 0.15.2; the repository moved to zig 0.16.0 on 2026-09-11 and both vendors require it | `.mise.toml`; `docs/guides/agent_resources.md` "Xcode And Zig Vendor Builds"; vendor `build.zig.zon` |

## Decided by the owner on 2026-09-17

| ID | Decision |
| --- | --- |
| H1 | "Reliable" means ten consecutive "CI / Test" runs pass on the first attempt with no job rerun |
| H2 | One viewer holds one development-host session. A client that opens a second session while its first is still open is not a supported shape; the integration test that does so is wrong and closes its first surface first. A same-viewer successor whose predecessor's stream has ended always gets a session |
| — | The structure in the Program Design is confirmed: bounded test concurrency, no blocking on the cooperative pool, per-owner quiescence composed per pipeline, event-driven test waits with a lint ban |
| — | Delivery is two stacked pull requests: everything except the bulk conversion first, which unblocks PR #350; the conversion of remaining polling waits stacked behind it |
| — | The first pull request merges after "CI / Test" passes on its head twice in a row on the first attempt, then PR #350 merges; run data is collected throughout ("run it 2. then merge pr, then merge 350. while doing this collect info"). Deliberately triggered runs count toward H1 |
| — | The release workflow moves to the new Xcode together with CI, in the first pull request |
| — | The serialized E2E lane, which runs in the local gate but not in CI, is added to CI in the second pull request |

## Not yet decided

| ID | Open meaning | Proposed by the orchestrator, not yet confirmed by the owner | Consequence of leaving it open |
| --- | --- | --- | --- |
| H3 | Whether the single content-hash mismatch in the product E2E (E8, `lane-bridgeweb-flakes.md` B2) is a product defect | Investigated separately; not counted as a flake and not fixed under this goal unless it reproduces on `main` | A real content-integrity defect could be mislabeled as flakiness |
| H4 | How far U4 and U5 reach into BridgeWeb browser tests, where waiting on a DOM condition is the library idiom and runs in a separate process from the app | BridgeWeb waits stay condition-driven, with one declared hang bound and no undeclared library default; they do not adopt the Swift no-polling ban | The owner's statements were made about Swift tests; applying them literally to the browser lane is a larger change nobody has asked for |
| H5 | Why the File surface reported no committed refresh for 120 s in the BridgeWeb annotation E2E (E8, `lane-bridgeweb-flakes.md` B1) | Diagnosed before any fix; until then the journey's failure reports which commands arrived | One failure family stays open; it does not block the first pull request |
