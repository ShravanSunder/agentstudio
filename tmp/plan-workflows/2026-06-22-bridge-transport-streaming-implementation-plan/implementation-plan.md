# Bridge Transport Streaming Implementation Plan

Date: 2026-06-22
Branch: luna-338-pierreshikitrees-review-viewer-2
Spec commit: ebad06d2
Plan status: Revised for `shravan-dev-workflow:plan-review-swarm`

This is an epic plan made of independently provable vertical tickets. Each
ticket must produce a real deliverable, not a half-change. Each ticket uses
TDD where behavior changes: add or adjust the smallest failing proof, observe
the expected failure, implement, then climb the proof pyramid only as far as
the ticket requires.

Do not begin implementation until this revised package passes plan review or
the owner explicitly accepts bounded residual risk.

## Source Coverage

Loaded source artifacts:

- `spec.md` lines 1-1160
- `review-protocol.md` lines 1-471
- `worktree-file-surface-protocol.md` lines 1-535
- `spec-review-report.md` lines 1-295
- `review-1.6.29/spec-review-report.md` lines 1-138
- current plan package:
  - `implementation-plan.md` lines 1-376
  - `file-organization.md` lines 1-392
  - `plan-ledger.md` lines 1-187
  - historical `plan-review-report.md` lines 1-319
  - `slices/00-carrier-proof.md` lines 1-143
  - `slices/01-transport-contracts.md` lines 1-157
  - `slices/02-review-protocol-vertical.md` lines 1-323
  - `slices/03-worktree-file-native-provider.md` lines 1-185
  - `slices/04-worktree-file-browser-surface.md` lines 1-209
  - `slices/05-hard-cutover-cleanup.md` lines 1-130
  - `lanes/codebase-boundary.md` lines 1-70
  - `lanes/validation-proof.md` lines 1-69
  - `lanes/execution-order-security-reliability.md` lines 1-67

Live repo anchors checked:

- `BridgeWeb/src/bridge/**`
- `BridgeWeb/src/app/**`
- `BridgeWeb/src/foundation/**`
- `BridgeWeb/src/review-viewer/**`
- `BridgeWeb/package.json`
- `.mise.toml`
- `Sources/AgentStudio/Features/Bridge/**`
- `Tests/AgentStudioTests/Features/Bridge/**`
- `scripts/bridge-web-sync-fixtures.sh`

## Product Outcome

Bridge becomes generic transport infrastructure for app-owned web panes.
Review and Worktree/File become application protocol families on top of the
generic transport. Large data stays out of Zustand. Provider authority remains
host-side. Browser code materializes projections, schedules demand, and adapts
prepared renderer inputs into Pierre without becoming the filesystem or Git
authority.

## Non-Goals

- Do not merge the PR.
- Do not add comment or agent-comms schemas beyond reserved fail-closed behavior.
- Do not move file/diff bodies, promises, AbortControllers, workers, or Pierre
  instances into Zustand.
- Do not rewrite Pierre/CodeView/Tree unless a proof failure shows a narrow
  materializer identity issue.
- Do not keep old and new fetch authority paths alive inside the same protocol
  after a ticket cuts over.
- Do not make the browser compute Git diffs or changeset clustering authority.

## Ticket Order

```text
00 intake carrier proof
  proves the selected intake carrier in real WKWebView before protocol migration

01 core transport contracts
  defines shared descriptor/resource/RPC boundaries and fixture parity

02 review protocol vertical with descriptor-backed demand
  makes Review frames authoritative and proves generic demand through Review

03 worktree/file native provider boundary
  creates host-owned Worktree/File source identity and descriptors

04 worktree/file browser surface
  creates the first browser surface and stale manual refresh proof

05 hard-cutover cleanup
  removes old mixed authority paths and runs final regression/canary gates
```

## Checkpoint Rules

Each checkpoint must satisfy:

- ticket-local red/green evidence for changed behavior
- unit proof for deterministic contracts/state machines
- integration or boundary proof for host/browser, registry, filesystem, or
  transport seams
- highest applicable product proof: browser integration, dev-server, WebKit,
  Swift, telemetry canary, benchmark, or PR gate
- reviewer handoff output with commands, exit codes, changed surfaces, and
  remaining risks
- checkpoint commit when scoped files changed and repo policy permits

A checkpoint commit is never proof by itself. It only records a proven state.
Do not stage unrelated files. If artifacts remain under ignored `tmp/`, either
force-add the accepted plan artifacts for the checkpoint or promote them to a
tracked docs location before committing.

If a broad repo-health gate fails outside a ticket's approved write scope, do
not edit unrelated infrastructure or product surfaces as part of that ticket.
Split the proof: require the ticket-scoped unit/integration/WebKit/quality gates
to pass, isolate and record the external blocker, and keep the broad gate open
for a separately scoped fix or final milestone proof.

## Requirements / Proof Matrix

| requirement or claim | source | owner | proof layer | evidence and freshness guard |
| --- | --- | --- | --- | --- |
| Carrier supports ordered intake frames before protocol migration | `spec.md` OD1 and stream lifecycle; plan review B1 | 00 | Swift/WebKit boundary, unit | real WKWebView burst/cancel/reset/stale-close proof from current worktree; no Review migration until it passes |
| Privileged RPC cannot be invoked from page-world events | `spec.md` 7.2; plan review B2 | 01 | security integration, browser integration | negative page-world tests for `__bridge_command`/`__bridge_ready`; content-world path works |
| Resource URL grammar, descriptor refs, leases, and integrity agree across TS/Swift | `spec.md` 6-7, 12-13; plan review I1/I5 | 01 | unit, Swift/WebKit boundary, fixture sync | shared accept/reject corpus, focused Bridge Swift/WebKit gates, and `scripts/bridge-web-sync-fixtures.sh` after fixture edits; broad Swift health remains a milestone/final guard when unrelated suites fail outside ticket scope |
| Demand scheduler is generic and does not learn Review package authority | `spec.md` 9; plan review B3/I2 | 02 | unit, architecture, integration | `core/demand` tests plus import checks; no raw Review resource URL authority in generic modules |
| Review frames attach descriptors before demand uses them | `review-protocol.md` 6-7; spec review addendum | 02 | unit, browser integration, Swift fixture parity | Review frame schema/materializer tests; shared TS/Swift fixture parity for snapshot/delta/invalidate/reset and descriptor registration order; source reset drops stale work |
| Review frames are app-internal transport; native leases remain byte authority | `spec.md` 7.1-7.2, 12-13; `review-protocol.md` 6, 11; user decision 2026-06-23 | 02 | browser/app integration, Swift/WebKit lease boundary, scheme-handler security tests | forged/stale/foreign page-world Review frames may not make unauthorized `agentstudio://resource/...` fetches succeed; native lease validation rejects cross-pane, old-generation, revoked, wrong-descriptor, or over-limit fetches; HMAC/encryption is deferred hardening, not a Ticket 02 gate |
| Bridge/provider errors are source-scrubbed before crossing into browser-visible surfaces | `spec.md` 7.2, 12, provider-scope validation | 01, 03 | Swift unit/integration, browser security unit | scheme-handler lease rejections and Worktree/File selector/canonicalization failures expose allowlisted reason codes only; no raw paths, cwd scopes, handle ids, capability URLs, or unsanitized provider error text cross the boundary |
| Review deltas support partial descriptor attachment without stale lineage reuse | `review-protocol.md` 6, 11; events 32-34 regression history | 02 | unit, integration, fixture parity | `review.delta` accepts optional `contentDescriptors`, merges unchanged same-lineage handles, and rejects omitted handles whose lineage changed; fixtures cover unchanged handle reuse and stale changed-handle rejection |
| Review changeset metadata remains flexible and non-authoritative | `review-protocol.md` 4, 10-11 | 02 | schema/materializer unit | live/closed/pinned, degraded confidence, overflow/fresh-scan fixtures; metadata cannot become content authority |
| Existing Review UX remains functional after migration | Review protocol proof expectations; current user bug context | 02 | browser/dev-server | browser integration and dev-server load smoke; `test:dev-server:worktree` remains green; the current full `test:dev-server` bounded scroll canary is ticket 03/04 stable-extent proof once provider size facts exist |
| Worktree/File provider mints source identity, descriptors, invalidations, and resets outside Review package lineage | `worktree-file-surface-protocol.md` 2, 5, 8; plan review B5 | 03 | Swift unit/integration | native tests prove non-Review host surface and provider-issued identity |
| Worktree/File provider canonicalizes and contains browser selectors | `spec.md` provider-scope validation; `worktree-file-surface-protocol.md` 5 | 03 | Swift security unit/integration | malicious path/cwd scopes, path hints, symlinks, traversal, and root tokens are rejected provider-side |
| Worktree/File provider publishes stable virtualized-size facts on earliest authoritative frames | `spec.md` 11; `worktree-file-surface-protocol.md` 6, 8, 10, 14; DiffsHub/Pierre research in workflow state | 03 | schema/model unit, Swift provider integration, fixture parity, telemetry schema fixture | `worktree.snapshot` and `worktree.treeWindow` carry `treeSizeFacts` with exact row count or conservative estimated total extent before tree row bodies hydrate; every `worktree.fileDescriptor` carries explicit `virtualizedExtentKind` plus exact `lineCount` or conservative `estimatedContentHeightPixels` before file content bytes are fetched/streamed; diagnostics schema is source-scrubbed |
| Browser Worktree/File surface preserves anchor-stable scroll extent from provider facts | `spec.md` 11; `worktree-file-surface-protocol.md` 10, 14; DiffsHub/Pierre research in workflow state | 04 | browser integration, browser benchmark, dev-server, telemetry canary | browser reserves tree/file extent from provider facts before hydrated body measurement; measured reconciliation preserves anchor item/offset; canary records scrollTop before/after, `scrollHeight` or virtualizer `totalSize` before/after, visible range, anchor item/offset, measured item ids, and reconciliation reason; canary fails on non-reset anchor identity change, drift over one row/line height, exact-count total-size change over tolerance, or unattributed estimated-height delta |
| Open file invalidation marks stale and does not auto-fetch until explicit refresh | `worktree-file-surface-protocol.md` 4, 9, OD-W1; plan review I4 | 04 | unit, browser/dev-server | stale marker -> no auto-fetch -> manual refresh fetches latest descriptor |
| Renderer adapters receive prepared render inputs only | `spec.md` 11 and proof expectations | 02, 04 | integration/browser | Pierre-facing adapters/rendered DOM contain prepared items/paths only, never fetchable Bridge URLs or descriptor authority |
| Comments/comms reserved resource kinds and flags fail closed | `spec.md` OD8; Worktree/File section 12; plan review I3 | 01, 04, 05 | schema/security unit | registry/parser tests reject disabled kinds/flags until a future schema slice exists |
| Telemetry excludes raw paths, source text, prompts, capability URLs, comments, and comms while retaining safe scheduler audit fields | `spec.md` 12-13; plan review I3 | 02, 04, 05 | telemetry canary | seeded Review and Worktree/File canary proof from current worktree; final cleanup reruns canaries |
| Large data stays out of Zustand | `spec.md` R3 and state placement | 02, 04, 05 | unit/state inspection | store snapshot tests prove refs/status/facts only after each app surface cutover |
| Worktree dev proof remains alive until Worktree/File replacement exists | plan review B4 | 02, 04 | dev-server | `test:dev-server:worktree` remains supported through Review migration, then proves new surface |

## Advancement Gates

- No ticket 01 until ticket 00 has real WKWebView carrier proof.
- No ticket 02 while privileged stream/open/refresh/cancel/reset RPC can still
  cross page-world events.
- No ticket 02 checkpoint, commit, or Worktree/File advancement while native
  lease/scheme-handler proof can be bypassed by a forged, stale, foreign, or
  over-limit Review descriptor/content URL. Page-message provenance is not a
  Ticket 02 security gate for the closed Swift app.
- No generic descriptor-backed demand authority before Review frames attach
  accepted descriptors.
- No removal of old Review-package Worktree dev scaffolding while
  `test:dev-server:worktree` still depends on it.
- No ticket 04 browser surface before ticket 03 publishes Worktree/File
  virtualized-size facts and proves schema/model, provider integration,
  provider/frame, and telemetry-schema fixture coverage for tree row count or
  estimated extent and file/code line count or estimated extent metadata.
- No ticket 04 checkpoint before browser proof consumes those provider facts and
  passes an anchor-preserving scroll-extent canary on the huge-worktree/dev-server
  path.
- No ticket 04 before ticket 03 proves provider-owned Worktree/File source
  identity outside Review package lineage.
- No ticket 05 until Review and Worktree/File replacement proofs both pass.
- No PR-ready wrapup while any checkpoint proof gate fails or lacks a named
  not-applicable reason.

## Review Cadence

- Ticket 00: checkpoint commit after carrier proof. Run implementation review if
  the carrier decision changes the transport shape beyond the current
  push/event path.
- Ticket 01: checkpoint commit and mandatory implementation review, because it
  changes the trust boundary.
- Ticket 02: checkpoint commit and mandatory implementation review before
  Worktree/File work starts.
- Ticket 03: checkpoint commit and mandatory implementation review before ticket
  04, focused on source identity, selector/path containment, descriptor
  issuance, reset/invalidation authority, and scrubbed extent diagnostics.
- Ticket 04: checkpoint commit and mandatory implementation review before
  cleanup.
- Ticket 05: checkpoint commit after final gates, then run final
  `implementation-review-swarm` and `implementation-pr-wrapup`.

## Execution DAG

```text
gate 0: reload accepted spec, current plan review, current repo anchors
  |
  v
ticket 00: intake carrier proof
  |
  v
ticket 01: core transport contracts and security boundary
  |
  v
ticket 02: Review protocol vertical + descriptor-backed demand
  |
  v
implementation review checkpoint for transport + Review
  |
  v
ticket 03: Worktree/File native provider boundary
  |
  v
ticket 04: Worktree/File browser surface
  |
  v
implementation review checkpoint for Worktree/File
  |
  v
ticket 05: hard-cutover cleanup and final gates
  |
  v
implementation-review-swarm
  |
  v
implementation-pr-wrapup
```

The work is intentionally serial. The repo supports independent proof better
than independent editing: 00/01 both touch transport-adjacent files, and 02/04
both touch app routing. Ticket 00 gates the carrier. Ticket 01 gates authority
and content-world security. Ticket 02 creates the first protocol router and the
first end-to-end app proof; it also provides descriptor-backed demand runtime
that ticket 04 reuses. Ticket 02 is not checkpoint-ready until native
lease/scheme-handler tests prove that forged, stale, foreign, or over-limit
Review descriptor/content URLs cannot fetch bytes. Page-world frame provenance
is treated as internal app transport for this closed Swift app. Ticket 02
is not the scroll-extent fix and must not be claimed complete by this design
delta. Ticket 03 can begin only after the shared
transport contract is stable, and it owns the DiffsHub-style stable
virtualized-size contract for Worktree/File: provider/materializer facts must
carry tree row/count/window metadata plus file/code extent kind, exact line
count, or conservative estimated-height metadata before hydrated body bytes are
fetched, streamed, or measured. Ticket 04 must follow ticket 03 because browser
Worktree/File cannot mint provider authority or invent stable virtualized
extents itself.

## Write Surfaces

Browser target layout is defined in `file-organization.md`.

- `BridgeWeb/src/core/models/**`: shared Zod schemas and `z.infer` TS types.
- `BridgeWeb/src/core/intake/**`: generic intake receiver/carrier contracts.
- `BridgeWeb/src/core/resources/**`: descriptor registry, resource URL parsing,
  integrity, and lease-facing helpers.
- `BridgeWeb/src/core/demand/**`: generic scheduler, executor, body registry,
  and demand contracts.
- `BridgeWeb/src/core/bridge-host/**`: host/browser integration, content-world
  RPC, and compatibility wrappers for existing bridge events.
- `BridgeWeb/src/features/review/**`: Review protocol schemas, materializer,
  demand policy, and fixtures.
- `BridgeWeb/src/features/worktree-file/**`: Worktree/File schemas,
  materializer, demand policy, and state.
- `BridgeWeb/src/review-viewer/**`: adapters only, with Pierre/CodeView/Tree
  touched only when proof requires a narrow renderer identity fix.
- `BridgeWeb/src/worktree-file-surface/**`: browser surface UI/runtime.

Swift target layout:

- `Sources/AgentStudio/Features/Bridge/Models/Transport/**`
- `Sources/AgentStudio/Features/Bridge/Transport/**`
- `Sources/AgentStudio/Features/Bridge/Runtime/**` generic runtime additions
- `Sources/AgentStudio/Features/Bridge/Models/ReviewProtocol/**`
- `Sources/AgentStudio/Features/Bridge/Runtime/ReviewProtocol/**`
- `Sources/AgentStudio/Features/Bridge/Models/WorktreeFileSurface/**`
- `Sources/AgentStudio/Features/Bridge/Runtime/WorktreeFileSurface/**`
- existing `ReviewFoundation` remains transition source until proven replaced.

## Cross-Slice Rules

- Generic `src/core/**` must not import Review or Worktree/File feature modules.
- Generic Swift `Models/Transport` and `Transport` must not own app semantics.
- App protocol frames attach descriptors before materializer or demand policy
  receives descriptor refs.
- Demand policy is app-specific; scheduler and executor are generic.
- Scheduler lanes are generic: `foreground`, `active`, `visible`, `nearby`,
  `speculative`, `idle`.
- No demand comes from page-world descriptor-like data. Trusted content-world
  adapters must re-resolve raw selectors through the current projection registry.
- Resource URLs are opaque capabilities backed by host-side lease validation.
- Ranged/chunked reads are preview-only until chunk manifests exist.
- Binary or oversized files degrade to metadata-only or bounded preview.
- Virtualized-size facts are stable metadata, not hydrated bodies; providers and
  protocol materializers publish them before renderer body measurement and, for
  Worktree/File, before tree/file content bytes are fetched or streamed.
- Comments/comms flags and resource kinds stay disabled/fail-closed in this epic.
- Telemetry is allowlisted and must not export raw path, text, prompt, handle,
  capability URL, comment, or comms seeds.

## Checkpoint Handoff Packet

Each implementation checkpoint handoff must include:

- exact checkpoint commit hash, or the reason no commit was made
- commands run, exit status, and pass/fail counts where available
- fixture-sync status when shared fixtures changed
- residual risks explicitly accepted
- legacy paths intentionally preserved
- current authority identity tuple:
  `paneId`, protocol, resource kind, descriptor/source/package identity,
  generation/revision/cursor as applicable
- scheduler/backpressure constants in force
- whether Worktree dev proof still uses Review scaffolding
- whether page-world ingress for descriptor-registering frames is removed from
  the authority path; temporary fences are not ticket-02 checkpoint proof
- telemetry/canary coverage completed so far and what is deferred
- for ticket 02, forged page-world Review frame proof and admitted host-origin
  frame proof for descriptor registration, package lineage replacement, demand,
  and fetch behavior, including the exact Swift/WebKit suite and browser/app
  integration cases used
- for ticket 03, sample `treeSizeFacts` and file-descriptor
  `virtualizedExtentKind` outputs that show exact and conservative estimated
  extent cases before content bytes, plus source-scrubbed diagnostics schema
- for ticket 04, scroll-extent telemetry canary output including scrollTop
  before/after, `scrollHeight` or virtualizer `totalSize` before/after, visible
  range, anchor item/offset, measured item ids, reconciliation reason, and
  pass/fail result for the stable-anchor/bounded-drift/exact-size-tolerance/
  attributed-height-delta contract

## Stop / Replan Triggers

- Existing push/event path cannot prove real WKWebView ordered/bounded delivery.
- Content-world-only privileged RPC cannot be represented without a new host
  bridge surface.
- Native descriptor/lease authority cannot reject forged, stale, foreign, or
  over-limit Review content fetches at the `BridgeSchemeHandler` boundary.
- Descriptor/lease authority cannot be enforced by `BridgeSchemeHandler`.
- Review materialization still requires CodeView remount on same-lineage deltas.
- Worktree/File provider cannot mint stable source identity outside Review
  package lineage.
- A proof gate fails outside the ticket scope. Stop code edits, split scoped
  checkpoint proof from broad repo health, and report the external blocker
  before changing infrastructure.

## Final Done Gate

Run ticket-local gates first. Before PR-ready wrapup, run:

```bash
pnpm --dir BridgeWeb run check
pnpm --dir BridgeWeb run test
pnpm --dir BridgeWeb run test:browser:integration -- \
  src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx
pnpm --dir BridgeWeb run test:browser:integration -- \
  src/worktree-file-surface/test-support/worktree-file-surface.browser.integration.browser.test.tsx
pnpm --dir BridgeWeb run test:dev-server
pnpm --dir BridgeWeb run test:dev-server:worktree
pnpm --dir BridgeWeb run benchmark:viewer
pnpm --dir BridgeWeb run test:benchmark:browser
mise run lint
mise run test
```

If a gate is not run, the handoff must name the blocker and the highest proof
layer that did pass.

## Slice Files

- `slices/00-carrier-proof.md`
- `slices/01-transport-contracts.md`
- `slices/02-review-protocol-vertical.md`
- `slices/03-worktree-file-native-provider.md`
- `slices/04-worktree-file-browser-surface.md`
- `slices/05-hard-cutover-cleanup.md`

## Next Workflow

Run `shravan-dev-workflow:plan-review-swarm` on this revised plan package.

phase_result: complete
evidence: revised plan package paths and source coverage above
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: The reviewed plan blockers have been folded into a revised checkpointed implementation plan.
