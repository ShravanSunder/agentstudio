# PR #344 — help needed: unresolved failures and questions

Date: 2026-09-13. Status: **incomplete; escalation for independent diagnosis**.

The requested outcome is reliable shared local/CI validation and a merge-ready, unmerged PR. We have spent the day making corrections but have not delivered an updated PR. Passing individual tests does not close the remaining failure mechanisms.

## Current state — read this first

- PR: https://github.com/ShravanSunder/agentstudio/pull/344
- Workspace: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.repo-bugs`, branch `repo-bugs`.
- Last verified pushed head: `90fe282845064bd00b1198896645057d9fb078e0`. Last fetched main: `1c29cc64ae060c7f6dbd3cac52f90296334d09e9`, already contained. These are saved Operator receipts, not a fresh GitHub query.
- The follow-up is **23 staged files**, not committed or pushed. Their current contents still match `tmp/ci-reliability-2026-09-13/final-validated-files-v7.json` exactly. The staged diff is `tmp/ci-reliability-2026-09-13/final-harness-v7-staged.diff`.
- Latest hosted result still concerns the older pushed head: browser and backend stress failed; Swift, quality, and site passed. Run: https://github.com/ShravanSunder/agentstudio/actions/runs/34764766262
- **Newly checked local evidence:** `harness-reliability-aggregate-v7.log` reaches final E2E completion and contains no explicit failure markers. It records 2,385 Bridge units, 25 Node integration tests, 463 browser tests (6 existing skips), stress 1, ordinary E2E 26, Swift fast 4,923/731, broad large 314/57, workload lane 81/5, and final E2E 6/3 passing. The test Operator hit a usage limit before returning the final process-exit receipt. **Recover that receipt before claiming aggregate exit 0; do not automatically rerun everything.**
- This escalation file was created after the test run and is outside the 23-file staged source snapshot.
- Further fixes and publication are paused for this escalation. No new Fable requests. No app merge, release, production changes, or service restarts. The latest continuation wake has finished; no renewal was requested.

## Most actionable finding from the subsequent read-only audit

**The stale-bootstrap/context race is now reproduced by a controlled real-component regression test. The normal control passes; forced overlap loses the final tree. The historical HTTP timeout has no trace establishing this was its exact occurrence.**

1. The session commits a subscription before its provider callback runs. Stream replay can see that committed subscription and start bootstrap A.
2. The delayed subscription-open callback starts bootstrap B for the same subscription. Replacement cancels A but permits overlap.
3. Bootstrap A has no cancellation check before calling the source operation. If A starts/resumes after cancellation, it can still enter File source initialization.
4. File initialization removes the subscription context and installs a new generation. Cancelled A can therefore replace B's context while B is suspended after source acceptance.
5. B's subsequent source-identity guard fails and returns without a final tree. A later exits as cancelled; task-ID guards ignore A's old completion and can regard B as complete. No final tree or replacement bootstrap is guaranteed.

Source anchors: `BridgeProductSchemeControlDispatcher.swift:112`, `BridgePaneProductMetadataCoordinator.swift:266` and `:442`, `BridgePaneProductMetadataCoordinator+ProducerLifecycle.swift:92` and `:183`, `BridgePaneProductFileMetadataSource.swift:159` and `:590`, and `BridgePaneProductFileMetadataSource+SharedConstruction.swift:38`. These live under `Sources/AgentStudio/Features/Bridge/Transport/`.

**Smallest proof:** extend the existing `BridgeMetadataCoordinatorProducerTaskTests` with the real `ProductFileSourceFixture`. Hold only A at the existing bootstrap trace callback; start B and hold B at its source-accepted observer; release cancelled A; then release B and join task completions. Assert a final current-subscription tree window, with no reset. Do not use the existing fake replacement source alone—it cannot prove context overwriting. No sleeps or new product test hooks are needed.

**Question for the helper:** prove or falsify this exact schedule before proposing a fix. Existing tests intentionally permit replacement tasks to overlap, so do not assume serializing all bootstraps is the correct repair. Inspect cancellation checks and context ownership at the existing boundaries. The user subsequently authorized the permanent regression test. It is now added; product code remains unchanged.

Five additional prepared HTTP reproductions passed (2.04–3.58 seconds). Those passes do not falsify this controlled interleaving or establish that the original intermittent failure is resolved. Logs: `tmp/ci-reliability-2026-09-13/file-opening-capture-1.log` through `file-opening-capture-5.log`.

## 1. File-source opening intermittently never completes

**Observed:** the real Swift/Vite File-session integration test timed out at 15 seconds in aggregate v6. A focused reproduction identified `source.opening`. Detailed opening probes then passed in four fresh runs, around two seconds each. The failed run does not identify the inner handshake operation.

**Known defect corrected:** the verifier ignored native subscription reset/end/cancellation and stream-error frames while waiting for successful data. It could turn an actual native failure into a generic timeout. Controlled real-codec tests reproduced four failures; ordered terminal handling now passes seven cases, preserving ACK order, expected cancellation, unrelated-subscription handling, and reader cleanup. This improves failure reporting; it **does not prove the native cause of the intermittent stall is fixed**.

**Questions needing help:**

1. Which exact completion is missing: bootstrap/control response, metadata-stream acceptance, subscription start, File source acceptance, initial tree construction, or a frame ACK?
2. Is a native failure/reset being concealed, or does a request remain pending without a terminal outcome?
3. Can we force the actual failing interleaving with existing admission/producer/transport controls?
4. Does this standalone verifier's partial protocol implementation differ materially from the production transport? Establish that difference before proposing a rewrite or recovery loop.

**Start here:**

- `tmp/ci-reliability-2026-09-13/product-file-session-opening-diagnosis.md`
- `tmp/ci-reliability-2026-09-13/product-file-session-diagnostic-v2.log` — reproduced outer opening timeout.
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server/product-file-session.ts` — opening checkpoints and sequential ACK/fetch waits.
- `BridgeWeb/scripts/verify-bridge-viewer-worktree-dev-server/product-file-session-metadata-frames.ts` and its unit test — corrected terminal handling.
- `Sources/AgentStudio/Features/Bridge/Transport/BridgePaneProductMetadataCoordinator+ProducerLifecycle.swift` — native bootstrap failure can enqueue a reset.

## 2. Large Review metadata sometimes does not converge after reload

**Observed:** earlier local stress attempts reached the second successful bootstrap and File readiness, but Review remained “Waiting for review metadata / Update unavailable.” A candidate started without a corresponding ready, failed, or complete-display observation.

**Not established:** a retry storm, wrong binary, or a common cause with File opening. Thousands of recorded aborted requests were cumulative and mostly had matching 204 responses; they are not proof of a retry loop.

**What was added:** native 1,699-item replay coverage using the existing shared protocol client; a real browser Worker publication test; worker-health and native comparison-state diagnostics. These bound individual connections, but have not reproduced the original combined failure causally.

**Questions needing help:**

1. Where does the native publication → stream/ACK → Worker assembly → display path first diverge on the failing reload?
2. Are we missing a cancellation, generation, stream-retirement, or final-window transition?
3. What smallest controlled integration scenario exercises that transition through the real participating components?

**Start here:**

- `tmp/ci-reliability-2026-09-13/annotation-act-aggregate.log`
- `BridgeWeb/tests/e2e/bridge-viewer-vite-review-render-observation.ts`
- `Tests/AgentStudioTests/Features/Bridge/BridgeDevelopmentHostReviewReplayTests.swift`
- `BridgeWeb/src/core/comm-worker/comm-runtime-protocol.review-windowed-publication.browser.test.ts`

## 3. Catalog performance gate: real long work or incorrect attribution?

**Observed:** both hosted stress attempts on `90fe28284` counted one long task where the gate requires zero.

**Measurement limitation:** the helper counts every browser Long Task overlapping the continuous interval from catalog begin to commit. Catalog windows run in separate callbacks, so unrelated work can happen between them. Existing timestamps alone do not prove which work caused the long task. Some phase timestamps are recorded after the measured work; Long Task duration precision also matters.

**What was added:** exact matched tasks and catalog stage samples now survive subsequent journey failures. The zero-long-task assertion and overlap filter remain unchanged.

**Questions needing help:**

1. Can a failing capture attribute the task to catalog staging/encoding, rendering, or unrelated work between callbacks?
2. What does the existing performance requirement actually constrain, and does the measurement implement it faithfully?
3. What minimal trace/profile distinguishes those cases while preserving the required gate? Do not narrow the filter or raise thresholds just to pass.

**Start here:**

- `tmp/ci-reliability-2026-09-13/final-90fe/annotation-backpressure-evidence.json`
- `BridgeWeb/tests/e2e/bridge-viewer-vite-annotation-catalog-performance.ts`
- `BridgeWeb/tests/e2e/bridge-viewer-vite-annotation-backpressure-journey.ts`

## 4. Shared harness resource classification needs scrutiny

A trivial fake zmx inventory command exhausted its unchanged five-second cleanup deadline in the broad large lane. Its suite was missing from the separate subprocess-workload lane used by analogous Sidebar tests. The classification contract failed before correction and passed afterward. The complete corrected large lane passed; padded cleanup took 0.332 seconds.

**Remaining question:** is the existing resource classification sufficient on CI? The lane named “serial large” still permits its few Swift Testing suites to overlap; it is not universal process isolation. Do not confuse `@Suite(.serialized)` or SwiftPM worker flags with cross-suite isolation. Do not increase the cleanup deadline as a substitute for diagnosis.

Evidence: `large-lane-process-contention.md`, `workload-lane-contract-red.log`, and `workload-lane-large-green.log`, all under `tmp/ci-reliability-2026-09-13/`.

## Corrections already demonstrated — avoid rediscovering them

| Correction | Evidence and limit |
|---|---|
| Shared annotation motion helper waits for terminal DOM state inside `act`; private copy removed | Controlled RED: 24px instead of auto. Affected 34 browser tests and full browser lane passed. |
| Forge final-branch test awaits invalidation, timer cancellation, and the actor's completed deadline decision | Full v4 reproduced the extra request and hung fake-provider cleanup. Focused 24/3 and later full-run Forge coverage passed. |
| Worker publication test uses a real Worker with realm termination | Replaced an in-process test that could not join private consumers. Real Worker test and bounded source review passed. |
| Staged source manifest synchronized | I left an obsolete deleted Node test staged; workload fingerprinting then tried to read it. Corrected index and byte comparison removed this self-inflicted input failure. |
| Verifier terminal errors surface immediately | Four controlled RED cases; seven GREEN cases, BridgeWeb check, and real File integration passed. Native stall cause remains open. |

The original repository lifecycle implementation is not being reopened here. Its behavior includes internal hiding, same-path ID restoration, distinct unproven paths, authoritative 30-day collection, and clearing optional pane references while preserving panes, terminals, Undo, and annotations. Original background: `docs/specs/2026-09-11-repository-lifecycle/` and `tmp/plan-workflows/2026-09-12-repository-lifecycle-integrated-delivery.md`. The current harness work is governed by the user's direct repair request; this packet is not a new implementation plan or a readiness approval.

## Why delivery has stalled

- Several independent failure classes have been grouped under “CI flakiness”; a fix for one has repeatedly been mistaken for broader progress.
- Missing first-divergence evidence left some failures as generic timeouts.
- Full-suite runs exposed additional defects and a staging mistake after focused gates passed.
- Follow-up changes stayed unpushed during this loop, so local results did not update the CI run the user was watching.
- The test Operator's usage limit interrupted the final receipt. That is a recent operational obstacle, not an explanation for the whole day's delay.

## Help requested and immediate sequence

We need **read-only expert triage from someone familiar with Swift concurrency and streaming browser/Node protocols**, plus browser performance attribution for issue 3. These are engineering/evidence questions, not unresolved product preferences for the user.

1. Recover final aggregate v7 exit status and confirm the exact 23-file source/index snapshot. Reuse saved proof where valid.
2. Prioritize one unresolved failure above and return the exact violated contract, source owner, and smallest discriminating reproduction. Clearly label hypotheses.
3. Recommend the smallest correction at the existing owner. No new retry loops, timeout inflation, weakened assertions, blanket serialization, or speculative architectural rewrite.
4. Once the user resumes implementation and remaining gates are satisfied, use the Git/GitHub Operator to commit, verify committed bytes, push, and inspect current-head CI/comments/threads/mergeability. Do not merge.

The broader inventory covers 157 runs and 171 failed-job logs: `tmp/ci-reliability-2026-09-13/ci-reliability-inventory.md`. It is historical evidence, not proof all listed failures are fixed.

## Copy-paste request for help

Read `docs/wip/2026-09-13-pr344-help-needed.md` in `/Users/shravansunder/Documents/dev/project-dev/agent-studio.repo-bugs`. Diagnose the unresolved failures using the linked source and logs. Read-only: do not edit code, retry CI, launch Fable, push, merge, or change services. First distinguish proven harness defects from unproven native/performance causes. Return the highest-priority cause or evidence gap, exact source anchors, and the smallest controlled reproduction or missing capture. Do not repeat the entire validation/review cycle.

## Controlled reproduction result

Command: `mise run test:swift -- --filter 'BridgePaneProductMetadataBootstrapContextTests'`. Exit1:2tests,1passed,1failed,1issue. The unperturbed realFile control passed; the forced replay/committed-open overlap failed because `finalTreeSources` was empty instead of containing the replacement source. Both producers completed and the trailing cancellation was acknowledged before assertions; no wall-clock or yield assumptions. Test execution took0.019s; total task56.42s.

Test: `Tests/AgentStudioTests/Features/Bridge/BridgePaneProductMetadataBootstrapContextTests.swift`. Log: `tmp/ci-reliability-2026-09-13/bootstrap-context-red-v2.log`. Initial schema-reference compile errors were corrected in the new test only and are not counted as the regression. Product code unchanged.

## Authorized bounded product correction and focused GREEN

The user subsequently authorized the smallest product fix and focused/aggregate proof. The existing cancellation check now runs before every producer operation, including bootstraps with no predecessor. The real File source checks cancellation before removing a context and after its awaited release, before installing a new context. These checks close both the demonstrated cancelled-before-operation schedule and the subsequent actor-entry/release window without serializing bootstrap replacement or adding a generation mechanism.

Focused command: `mise run test:swift -- --filter 'BridgePaneProductMetadataBootstrapContextTests|BridgeMetadataCoordinatorProducerTaskTests'`. Exit0,9tests/2suites passed; both normal and previously RED overlap cases passed. Evidence: `tmp/ci-reliability-2026-09-13/bootstrap-context-green-v2.log`. Source review found no remaining issue in this bounded ownership reversal. A standalone SwiftLint invocation reported zero violations but exited1 on cache permissions; this is not claimed as a passing lint command. Required full `mise run --raw test` is now Operator-owned, log `bootstrap-race-aggregate.log`. No aggregate success or PR readiness claim yet.
