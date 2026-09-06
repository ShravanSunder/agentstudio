# Stable release takeover investigation

## Scope and current evidence

The requested outcome is a stable release addressing the remaining performance, atom-retention,
and Ghostty lifecycle problems. The disk incident is resolved by the owner's cleanup; it is not
evidence of an application leak. Review-comment work, including agentstudio-git PR #10, is excluded.

The takeover branch starts at fetched AgentStudio origin/main `afa8fc15b`. Existing branches and
untracked work were preserved. Recovery archives under `tmp/takeover-2026-09-05/` contain 18
modified/untracked files from perf-residuals, two from atom-hygiene, and six from memory-issues;
archive inventories were checked against Git's changed-file lists. These are recovery copies,
not reviewed or committed implementation.

## CI failures

### PR #331: real filesystem events enter a synthetic-event assertion

Current remote head: `f298d8a1c`. CI run `33993392153` reports
`FilesystemActorActivityTests.swift:301`: actual cursor watermark `28562263`, expected `89`.
The test failed after 0.009 seconds. It creates a real `DarwinFSEventStreamClient`, injects a
synthetic event with ID 89, shuts down, and checks the first commit's watermark. It does not
invoke its private yield-wait helper. The default client factory starts native observation;
the same client supports an injected local stream factory used by neighboring boundary tests.

Leading hypothesis: native callbacks race with synthetic input and advance the watermark.
The proposed correction is to control native stream lifetime for the synthetic activity tests,
retaining the real ingress, actor, projector, and shutdown path and the exact watermark assertion.
Raw CI evidence: `tmp/takeover-2026-09-05/pr331-failed.log`.

### PR #332: cadence test, cause not yet established

Current remote head: `30e451c20`. CI run `33999522619` reports five issues in
`unchangedResultsLengthenPeriodicCadence`, beginning at line 442, after 66.376 seconds.
The private helper has a turn budget without a deadline. That is a robustness concern, but
the test also advances an injected clock while visibility admission and deadline tasks settle.
The scheduler records status duty using `ContinuousClock`, then enforces a cooldown four times
that duration against its injected scheduling clock. The test assumed 240 ms always sufficed;
under contention measured duty can make that false. The correction asserts the scheduled
deadline against both the expected adaptive cadence and measured duty, then advances to that
deadline. The private predicate waiter now uses a ten-second monotonic bound.
Raw CI evidence: `tmp/takeover-2026-09-05/pr332-failed.log`.

The inherited claim that both failures share one yield-budget cause is contradicted by #331's
source and actual failure value. Do not merge on a lucky rerun.

Current local proof: the original two suites passed 20/20 (no local reproduction) and the
corrected suites passed 20/20, both through `mise run test:swift -- --filter
'FilesystemActorActivityTests|GitWorkingDirectoryProjectorVisibleTierTests'`, exit 0.
`mise run lint` passed, exit 0, with zero SwiftLint violations and architecture lint OK.
The correction preserves all exact synthetic cursor assertions and the real actor/projector
shutdown path while replacing only native event-stream lifetime in synthetic-input tests.

## Git package integration

Remote package main is `474bf342`; remote `fix/demand-driven-refresh` is `c8dbd7ef`.
AgentStudio main already pins `c8dbd7ef` in both Package.swift and Package.resolved.
Package main is an ancestor of that branch. Six commits remain unmerged, spanning separated
status facts/detail, exact-clean observation contracts, staged remote refs, guarded atomic
promotion, bounded cleanup, and in-process promotion.

The current AgentStudio demand-driven Git program design explains why these capabilities are
required: avoid redundant traversals while retaining exact Git authority; publish fetched refs
only for current captured identity; use in-process promotion for correct OwnEvent attribution.
Moving the application pin to package main now would remove these capabilities.

Package validation must include `mise run check`. Prior app documentation reports that a
package check stopped at its Bridge consumer compatibility harness; this needs current
verification against the intended consumer without importing excluded review-comment work.
The current check reproduced an earlier status-harness omission: the provider now references
clean-continuity contracts that were absent from the extracted source. The one-file test-harness
correction reads those declarations from the real consumer. Recheck passed build, lint, and
202 tests, including all seven status compatibility tests, before failing both Bridge harness
tests with four issues. Five comparison/contribution contract types already present in app main
are omitted from the Bridge harness. That test-only follow-up is pending an explicit scope
decision; no excluded product changes were made and no required test was skipped.
The APFS branch named `apfs-cow-worktrees` is an old SDK commit, not evidence of a delivered
CoW feature. Its separate design branch contains a design-only commit.

## Memory and performance work requiring proof

PR #332's requirements retain the Ghostty pin and 300-second undo grace. Existing runtime
reports establish useful lower-layer evidence: 20 released surfaces were freed after expiry,
and corrected tab undo restored the same 12 surfaces. Those runs used older heads and an
occluded window. They do not prove current-head visible-to-hidden transitions or visual return.

Required current native scenarios include tab switch and return with continuing output, zoom,
drawer collapse, pane minimize, arrangement switch, cross-tab move, app hide, miniaturize,
close/expiry, pane undo in a non-empty tab, and tab undo. Bridge/webview hosting must remain
sound where shared host retirement changed. Record renderer conservation, thread/PTY counts,
memory before and after repeated cycles, and post-expiry behavior. Investigate the reported
quit drain hang and unexplained long-running growth separately from bounded live graphics memory.

Perf-residuals contains observation re-arm corrections and main-thread attribution work.
Atom-hygiene contains three unpushed commits plus uncommitted slot-release behavior; its own
documentation retracts the premise that pane/tab identifiers never recur. Both require source
reconstruction and bounded review before integration.

## Additional old-memory handoff validation (2026-09-06)

Read all 422 lines of `agent-studio.memory-issues/docs/wip/2026-09-05-memory-issues-takeover/implementation-handoff.md`
and its one-line prompt. All 47 relative file links resolve. The named historical Jetsam
reports are no longer present at the supplied Retired location; their numerical findings remain
historical audit evidence, not fresh measurements.

The handoff correctly separates renderer ownership, graphics/compositor growth, and terminal
process-family growth. Current proof must preserve those distinctions. Add fixed-population
resize/geometry checks and process-family counts to the native observations; do not claim that
surface conservation alone resolves the historical incidents.

Its startup account is superseded by main's geometry-driven hydration contract: eligible hidden
terminals stay in the startup cohort and follow visible main/drawer work. Visibility controls
priority and drawing, while safe geometry controls hydration eligibility. The old demand-only
restart expectation must not be imposed on current main.

The old dirty drawer helper explicitly toggles the drawer open after the workload. This is
fixture normalization, not a demonstrated fix for persistence. Current restart proof must
observe drawer state before shutdown and after restore without that normalization.

Fresh PR #332 debug head `30e451c20` launched in attached fallback mode as PID 9190, ath5,
marker `debug-observability-ath5-1788660716-4765`; native screenshot showed a shell prompt.
LaunchServices failed with -10810; detached fallback exited. Attached fallback remained alive.
This is debug behavior evidence only, not signed/notarized release launch proof.

The first full aggregate of the takeover correction failed another visible-tier cadence case:
`filesystem refresh updates cadence from complete result equality`, eight issues. It shared
the assumption that fake-clock cadence elapsed regardless of real duty cooldown. Its first
two periodic advances now use the recorded deadline. Focused rerun passed 20/20; aggregate
revalidation remains pending. No production scheduling policy changed.

## Outstanding release verification

No release readiness claim yet. Require scoped red/green proof, current aggregate `mise run test`,
lint, native lifecycle and memory proof, current implementation review, PR checks and threads,
mergeability, release-script validation, and downloaded stable artifact signature/notarization
and cask digest verification. Do not weaken a gate or broaden into excluded code to pass it.

## Native tab and drawer observation (2026-09-06)

At PR #332 head 30e451c20, ath5 PID 9190 displayed its original terminal prompt.
Through the native UI, created a second terminal tab, closed it, and used Edit > Undo Close Tab.
Marker evidence recorded closed_for_undo at 09:28:52Z and undo_restored at 09:29:09Z without
a new creation. Added a drawer child at 09:29:35Z, collapsed/reopened it, and captured a
rendered parent and drawer shell prompt. The next creation is attributable to that drawer.

Closed the second tab and drawer at 09:30:23.768Z/09:30:23.769Z. Telemetry then reported
created=3, active=1, close_undo=2, live=3, managed=3, orphan=0. No artificial TTL reduction.
A separate operator owns the post-expiry sample; no further UI mutation during that capture.

Current window telemetry now includes visible=true, occluded=false and real transitions
between occluded=true/false, with changed renderer deliveries. This improves on the old
always-occluded run, but is not yet the complete 30-pane, multi-scenario release proof.

## Paused-lane admission gaps

Perf-residuals' latest observation specification requires same-turn A→B→C to publish only C.
Its uncommitted PaneFocusTracker still publishes the pre-mutation value synchronously and
re-arms there; its test still expects a gain ending within the same turn. The implementation
and test must be reconciled with the latest specification before adoption.

Atom-hygiene's amended design explicitly says reclamation moves from atom removal to the
undo owner, because IDs recur. It records this as an ownership change returned to the owner,
not an implemented accepted call-site change. Its existing release API comment still claims
pane/tab IDs never recur. No production call site should consume that API under this premise.

The new main-thread stall instrument also retains explicit owner decisions about adding the
telemetry family and exporting scrubbed function names. Those are pending in this conversation.
