# SDK Frontier review reduction

The initial findings below are historical. The final bounded source-review
reduction at the end records their disposition; delivery gates remain separate.

Candidate: agentstudio-git f610592913cb10d54eef1a4b925dad4062e63859.
Base: 474bf34210dd8e176f9b3585b061161a8e8b50d4.
Reviewer: fresh-context gpt-6-astra, high, sdk_frontier_review.
Read-only was declared, not OS-enforced by native spawn; reviewer reported no
mutations and parent independently verified clean candidate state.
User explicitly authorized full current-source review despite incomplete
historical slice plan. Historical remediation count remains unknown, not zero.

## Result: needs revision; main merge and release blocked

Parent accepted three source-backed findings:

1. Ref promotion atomicity. SDK LibGit2StagedFetchPromoter.swift65 calls
   git_transaction_commit. Pinned vendor/libgit2/include/git2/transaction.h101
   and src/libgit2/transaction.c349 explicitly apply refs one by one and stop on
   first failure, without rollback. Generic failure masks possible partial
   canonical changes; App RemoteReferenceRefreshActor.swift506 catches all
   failures and subsequently cleans staging. Required atomicity is not proven
   and the chosen primitive contradicts it. Owner: program-design decision,
   followed by bounded implementation. Confirm with late multi-ref failure
   injection, not only existing pre-commit conflict tests. No speculative
   rollback system or vendored change authorized.
2. Observation completeness. LibGit2StatusObservationIdentityReader.swift86
   records config entry origins, not absent/empty include targets. Missing
   external include can later change status without observed scope changes.
   Pinned config_file.c589 tolerates missing includes; App clean renewal uses
   witness rather than rereading configuration. Owner: existing observation
   reader. Include complete dependencies or mark unsupported. Confirm with
   missing/empty external include outside observed scopes and fresh exact status.
3. Credential-bearing URLs. GitRemoteContracts.swift74 public Codable snapshot
   exposes raw configured/effective URL fields assigned in StagedFetch.swift38.
   SDK Authentication spec81 forbids that returned/encoded exposure. Owner:
   existing capture/contracts boundary. Preserve private fetch provenance and
   redact public metadata, or settle explicit opaque capability contract.
   Confirm with synthetic credentials and fetch-provenance test; never redact
   the actual fetch URL blindly. No actual credentials inspected.

Direct source proof establishes all three contract violations. Actual late
write failure, missing-include renewal, and synthetic credential regressions
still need permanent tests; no runtime reproduction falsely claimed here.

## Covered without additional supported findings

Bounded commit traversal, bounded diff impact, complete/proportional Review,
opaque seed identity/recheck/fallback, LFS cleanliness, package linkage, copied
source harness removal, and five-file isolated App complete-consumer adaptation.
Reviewer found no metadata-stream content addition. These are scoped review
results, not proof of all application behavior.

## Evidence boundaries

SDK full check: exit0,247tests/26runs, universal pinned artifact, build/lint.
ASan and TSan each247tests/26runs under per-command Xcode26.6. Hosted binary not
instrumented by those Swift sanitizer runs. Original26.3 ASan startup deadlock
sample preserved; no SDK failure attribution from it.
Adapted isolated App main consumer46tests/4suites exit0; actual dependency pin
verified. Quality log ends successfully but exact exit could not be recovered.
Full PR A annotation/proportional integration, App aggregate/native/packaged,
CI/release and worktree cleanup remain outside completed proof.

## Next boundary

Do not merge/release. Ask owner to resolve atomicity guarantee versus explicit
indeterminate outcome; no silent weakening. Once scoped correction choices and
bounded remediation authority are settled, write failing tests, fix existing
owners, repeat affected proof and obtain fresh independent review.

## Final bounded source-review reduction

SDK candidate: `0b7b81aa6dc8db6155d275265f4d52698e71c5fa`.
App integration checkpoint: `c085c067aef663f7874619600fded6251bc5cc04`, branch
`sdk-consumer-integration-2026-09-08`, isolated from the shared UI checkout.

Owner approved partial canonical-ref changes on failure, honest failure
reporting and current-state reread, with no rollback or additional recovery
system. This settled the initial atomicity question; it did not weaken stale
origin/currentness rejection. Authority is recorded in TRANSPORT-0238.

SDK include-completeness and public credential-boundary regressions reproduced
the findings and passed after correction. Commit-stage failure now reports the
existing indeterminate outcome. Corrected SDK full check, ASan and TSan each
passed 250 tests over 26 suite invocations, exit 0. Live authenticated remote
smoke remains opt-in/skipped; prebuilt libgit2 is not instrumented by Swift
sanitizers. SDK rereview found no additional supported SDK correction issue.

App rereview exposed three related failure-path defects: recomputation was not
started, old-origin refs could be reaccepted under a replacement origin, and
demand contraction could skip invalidation. Permanent regressions reproduced
all three before correction. Existing actor, authority sink and local projector
now retain promotion custody, invalidate stale authority, conditionally restore
only same-origin local acceptance, and start/join represented-worktree reads
before failed settlement. There is no second fetch or new recovery owner.

Final fresh-context Astra review found no remaining behavioral issue. Its one
minor telemetry omission was reproduced with an existing recorder assertion
(2 tests, 1 expected issue, exit 1). Reusing the existing invalidation helper
fixed accounting and removed duplicate invalidation logic. Final 78 tests in
7 suites passed, exit 0; scoped formatting, SwiftLint and architecture checks
passed, exit 0. Focused independent closure returned ready for the source
correction and approved-policy wording. The parent inspected the helper, its
captured revision, regression, production wiring and final logs.

Evidence:

- `/private/tmp/agentstudio-promotion-invalidation-metric-red-permitted.log`
- `/private/tmp/agentstudio-promotion-invalidation-helper-green.log`
- `/private/tmp/agentstudio-promotion-invalidation-helper-quality.log`
- `/private/tmp/agentstudio-sdk-final-package-consumer.log`: umbrella/leaf smoke
  against hosted libgit2 1.9.4, exit 0.
- `/private/tmp/agentstudio-sdk-final-app-consumer.log`: exact-pin production
  consumer gate, 46 tests in 4 suites, exit 0.

This is scoped source-review acceptance, not SDK release or whole-App readiness.
SDK draft PR #11 is open; CI, final PR gates, merge/release and worktree cleanup
remain. Isolated App aggregate is in progress; shared PR A proportional,
annotation, current-UI and packaged/native proof remains distinct. App PR #316
must remain unmerged.
