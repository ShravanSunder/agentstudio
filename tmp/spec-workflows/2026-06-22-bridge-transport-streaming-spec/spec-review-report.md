# Bridge Transport Streaming Spec Review Report

Date: 2026-06-22
Status: Parent reducer after spec-review-swarm; superseded by the 1.6.29 addendum for current route

Reviewed artifacts:

- [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)
- [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1)
- [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)

Coverage evidence:

- Pre-review parent coverage: `spec.md` 711 lines, `review-protocol.md` 378
  then 385 lines after the tag fix, `worktree-file-surface-protocol.md` 367
  lines. Parent read every chunk before dispatch.
- Post-revision coverage: `spec.md` 863 lines, `review-protocol.md` 400 lines,
  `worktree-file-surface-protocol.md` 412 lines, `swarm-ledger.md` 133 lines.

Review lanes:

- Product/requirements: Goodall, answered, verdict `needs revision`.
- Architecture/contracts: Franklin, answered, verdict `needs revision before planning`.
- Security/threat model: Dirac, answered, verdict `needs revision before planning`.
- Validation/planning/adversarial crux: Fermat, answered, verdict `needs revision before plan-creation`.
- Original product lane Zeno was interrupted by parent patch notification and
  returned only an acknowledgement; parent did not use it as a substantive lane.

## Verdict

Revised after review. The design spine held, but the first review found
planning-blocking contract gaps. Parent accepted and patched the blocking/root
findings in the current artifacts.

Current next step: `shravan-dev-workflow:plan-review-swarm`, per the 1.6.29
addendum below. The older direct `plan-creation-swarm` recommendation is
superseded because the implementation plan now exists and has been revised.

## What Held

- Bridge remains generic transport, not Review IPC.
- Review remains the provider-computed comparison protocol.
- Worktree/File is one user-facing surface with internal tree/content/status
  contracts.
- Large bodies stay out of Zustand.
- Scheduling policy and generic backpressure remain separate.
- DiffsHub smoothness maps to incremental materialization and renderer deltas,
  not browser-owned Git diff authority.

## Accepted Findings And Edits

Accepted A1. Provider-owned identity looked browser-minted.

- Finding source: architecture lane B1.
- Edit: Review open request is now `ReviewOpenComparisonRequest` with
  `clientRequestId`; provider-issued package identity is returned in snapshot
  frames. Worktree source specs are request/selectors; provider mints source
  identity.
- Files: [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1), [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)

Accepted A2. Generic Bridge hardcoded app nouns.

- Finding source: architecture/product lanes.
- Edit: generic protocol ids/resource kinds are registered strings; concrete
  resource kind allowlists moved to app protocol specs.
- Files: [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1), [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1), [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)

Accepted A3. Capability URLs lacked binding/lifetime/replay contract.

- Finding source: security and validation lanes.
- Edit: added host-side lease binding, rejection cases, and no DOM/log/telemetry
  exposure rule.
- File: [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)

Accepted A4. Content-world RPC boundary was asserted, not specified.

- Finding source: security lane.
- Edit: added content-world-only ingress and page-world untrusted-data rule.
- File: [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)

Accepted A5. Partial/chunk integrity was security-sensitive and unresolved.

- Finding source: security and validation lanes.
- Edit: first implementation uses whole-body validation for authoritative
  resources when integrity is issued; ranged/chunked reads are preview-only
  until chunk manifests exist.
- File: [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)

Accepted A6. Stream lifecycle/gap/reset behavior was too thin.

- Finding source: validation lane.
- Edit: added opening/active/gapDetected/resetRequired/closed lifecycle with
  duplicate, missing, out-of-order, reset, and stale-result behavior.
- File: [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)

Accepted A7. Comments/comms were promised but not specified.

- Finding source: all substantive lanes.
- Edit: comments/comms are now future/reserved. Flags and resource kinds must
  fail closed or be disabled until the schema/permission/redaction slice exists.
- Files: [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1), [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)

Accepted A8. Proof expectations were labels, not fixtures.

- Finding source: validation and product lanes.
- Edit: parent proof section is now a compact matrix with layer, fixture,
  assertion, and prohibited substitute.
- File: [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)

Accepted A9. Review query used unknown payloads.

- Finding source: architecture lane.
- Edit: Review query now uses opaque `viewFilterToken`, `groupingKey`, and
  `provenanceFilterToken`.
- File: [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1)

Accepted A10. Oversized/binary file behavior was underdefined.

- Finding source: product/validation lanes.
- Edit: first behavior is metadata-only/unavailable for binary files and
  non-authoritative bounded preview for oversized text.
- File: [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)

## Contested Or Deferred

C1. Continuous stream carrier remains open.

- Classification: open planning gate, not accepted blocker after revision.
- Resolution: spec now requires a carrier proof spike before implementation
  chooses bridge-world push, custom-scheme fetch streaming, or EventSource-like
  streaming.

C2. Exact changeset clustering algorithm remains deferred.

- Classification: intentionally deferred.
- Resolution: contract now requires stable id, cursors/checkpoints,
  reason/algorithm metadata, confidence/degraded-mode metadata, limitations,
  and no browser diff authority. Runtime proof only applies when the plan
  implements clustering.

C3. Exact comment/comms schema remains deferred.

- Classification: future spec slice.
- Resolution: reserved-disabled until schema, permissions, redaction, stale
  anchors, and telemetry rules exist.

## Residual Open Decisions

- Carrier proof result and selected carrier.
- First implementation concurrency counts.
- Selected-neighborhood ordering.
- Review content revision authority details.
- Comment/comms schema slice.
- Future chunk manifest design.

## Security Status

Threat-model status: present and materially strengthened after review.

Security-sensitive surfaces now covered:

- capability URL leases and replay rejection
- content-world RPC ingress
- provider-scope canonicalization
- markdown inert rendering contract
- telemetry allowlist/canaries
- whole-body integrity and preview-only ranges

Remaining security work is planning/spec-slice scoped:

- concrete comments/comms permission/redaction model
- exact chunk manifest contract if authoritative ranges are introduced
- carrier-specific WKWebView streaming proof

## Proof Status

Proof expectations are present and fixture-shaped. Exact commands and suite
selection remain deferred to `plan-creation-swarm`, as intended.

## Parent Receipt

- Subagents produced candidate findings only.
- Parent accepted the overlapping blocker/root findings and patched the spec.
- No product code was changed.
- The artifacts live under ignored `tmp/`, so `git status` does not show them.

## Addendum: Demand Policy Scheduler Re-Review

Date: 2026-06-22
Status: resolved after focused re-review

Reviewed artifacts after the demand-policy revision:

- [spec.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md:1)
- [review-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md:1)
- [worktree-file-surface-protocol.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md:1)

Coverage evidence:

- Pre-review line counts after discriminated-stimulus edit:
  `spec.md` 1051, `review-protocol.md` 451,
  `worktree-file-surface-protocol.md` 473.
- Post-revision line counts after accepted patches:
  `spec.md` 1112, `review-protocol.md` 458,
  `worktree-file-surface-protocol.md` 483.
- Parent read all three artifacts before dispatch.

Review lanes:

- Architecture/contracts: Avicenna, answered, initial verdict `needs revision`,
  focused re-review `resolved`.
- Security/trust-boundary: Mill, answered, initial verdict `needs revision`,
  focused re-review `resolved`.
- Requirements/testability/planning-readiness: Turing, answered, initial verdict
  `needs revision`, focused re-review `resolved`.

Accepted findings and edits:

- Descriptor handoff was underspecified.
  Added `BridgeAttachedResourceDescriptor`, required attached descriptor
  registration before materializer/policy runs, and changed Review/Worktree
  frames to attach descriptors instead of exposing raw descriptor strings.
- Review ownership pulled generic scheduler/executor responsibilities back into
  the Review protocol.
  Changed Review ownership to app demand policy / demand-intent derivation and
  app lineage/commit guards; generic scheduling, execution, retry/abort, and
  stale completion drops remain shared Bridge runtime responsibilities.
- `DemandReadContext` was not internally coherent.
  Added `freshnessKey` to `DemandKeysSchema` and made all demand keys derive
  from authoritative descriptor identity across pane/protocol/source/package/
  generation/revision/cursor boundaries.
- Mixed-interest mapping was not table-testable.
  Defined `ViewInterest` as dominant current interest with precedence:
  `selected > open > visible > nearby > speculative > none`, and added a
  descriptor-state / body-window / interest truth table.
- Worktree stale-open behavior contradicted the manual-refresh default.
  Locked first implementation to manual refresh: `openFileInvalidated` marks
  stale and emits no content demand until `explicitRefresh`; initial file open
  maps to `foreground`.
- Worktree source authority bootstrap was inconsistent.
  `worktree.snapshot` now carries provider-issued
  `WorktreeFileSurfaceSourceIdentity`; echoed request selector is explicitly
  non-authoritative.
- `DemandStimulus` lacked a trusted ingress boundary.
  Added rule that only Bridge content-world materializers, provider/reset
  handlers, and trusted app-owned UI adapters can emit demand stimuli. Page
  world and rendered content provide raw selectors only and must be re-resolved
  through the current projection registry.
- Cause-free `DemandIntent` needed an audit replacement.
  Kept `DemandIntent` provenance-free, but required allowlisted
  scheduler/executor trace fields: `stimulusKind`, `stimulusOrigin`, `lane`,
  `dropReason`, and hashed current identity.
- Proof expectations did not pin the new contract.
  Added proof rows for descriptor handoff, demand-stimulus ingress, policy
  truth-table fixtures, source-reset demand invalidation, and scheduler audit
  telemetry.

Focused re-review result:

- Architecture/contracts resolved all targeted findings.
- Security/trust-boundary resolved all targeted findings.
- Requirements/testability/planning-readiness resolved all targeted findings.
- No remaining blocker or important finding from the re-review lanes.

Updated verdict:

The demand-policy / scheduler / executor contract is now planning-ready, subject
to the existing open decisions already called out in the spec. The next workflow
can be `plan-creation-swarm` for implementation sequencing and proof gates.

## Addendum: 1.6.29 Spec Review Refresh

Date: 2026-06-22
Status: ready for plan review after one tiny same-session spec edit

Refreshed review used `shravan-dev-workflow:spec-review-swarm` 1.6.29. Spawned
review lanes timed out under host file-descriptor pressure and were not used as
evidence. Parent reducer found one important wording contradiction: generic
integrity prose could be misread as enabling first-implementation comment/comms
resources, while OD8 and the Worktree/File protocol reserve those resources as
disabled/fail-closed.

Accepted edit:

- `spec.md` section 12 now states that comment and agent-comms resources are
  reserved-disabled in the first implementation, and the integrity rule applies
  only after a later schema slice enables those resource kinds.

Review artifact:

- [review-1.6.29/spec-review-report.md](/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start/tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-1.6.29/spec-review-report.md:1)

Result:

- No validated blocker remains before `plan-review-swarm`.
