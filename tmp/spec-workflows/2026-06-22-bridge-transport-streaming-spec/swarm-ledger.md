# Bridge transport streaming spec swarm ledger

Date: 2026-06-22
Workflow: research-swarm plus spec-creation-swarm

## 2026-06-22 Revision After Worktree/File Surface Alignment

Parent accepted a boundary correction from the design discussion:

- Worktree and FileView should not be modeled as separate user-facing apps.
- The target is one Worktree/File Surface protocol family in the same Vite app.
- Tree, file content, status, comments, and agent communications are internal
  subcontracts of that app surface.
- Open file content should preserve reader continuity: live source changes mark
  the open content stale and expose refresh instead of silently replacing it by
  default.
- Review remains separate because it is a provider-computed comparison protocol,
  not because it needs a different Vite app.

Artifact split:

- `spec.md` now owns generic Bridge transport, state placement, scheduling,
  backpressure, security, proof expectations, and cross-protocol decisions.
- `review-protocol.md` owns Review comparison, package, intake, provider-owned
  diff calculation, and deferred changeset clustering contracts.
- `worktree-file-surface-protocol.md` owns the unified Worktree/File Surface,
  tree windows, file descriptors/content sessions, status, invalidation, and
  reserved comments/comms substreams.

Accepted research additions:

- Local Claude Code checkout research found session-scoped baseline capture,
  touched-path grouping, atomic consume/restore of unreviewed state, and stable
  session identity in `plugins/security-guidance`. The checkout is shallow, so
  March 3 history was not locally provable.
- Prior-art research found Watchman-style settle clocks, Node/Chokidar
  write-stability/backpressure patterns, Git/VS Code staging/resource groups,
  and Claude/VS Code/Cursor-style chat checkpoints as compatible clustering
  families.
- The spec therefore defers the exact provider-owned changeset clustering
  algorithm while requiring stable cluster identity, cursors/checkpoints,
  reason/algorithm metadata, confidence/degraded-mode metadata, and explicit
  limitations for out-of-band edits.

Next route:

- Run `spec-review-swarm` over `spec.md`, `review-protocol.md`, and
  `worktree-file-surface-protocol.md`.

Review result:

- `spec-review-swarm` ran product/requirements, architecture/contracts,
  security/threat-model, and validation/planning lanes.
- The first review verdict was `needs revision`.
- Parent accepted and patched root findings around provider-issued identity,
  generic Bridge registration, capability URL leases, content-world RPC ingress,
  partial integrity, stream lifecycle, comments/comms deferral, proof fixtures,
  Review query tokens, and binary/oversized file behavior.
- Reducer report:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec-review-report.md`

## Subagent lanes used

- Ptolemy: current Bridge transport boundaries.
- Hubble: Pierre view boundaries.
- Lovelace: streaming protocol prior art.
- Bernoulli: scheduler/backpressure state model.
- Copernicus: DiffsHub backpressure.
- Anscombe: backpressure technique taxonomy.
- Mencius: security/trust boundary.
- Descartes: current materialization invalidation semantics.
- Rawls: Pierre renderer contract.
- Hilbert: changeset intake model.
- Schrodinger: Review source subscription and provider-owned diff boundary.
- Sartre: Worktree source subscription and non-Review worktree explorer boundary.

## Synthesis decisions

- Bridge is generic transport infrastructure. Review systems provide domain
  descriptors and resource semantics.
- Continuous streams carry compact invalidation/fact events only.
- Bounded resource streams carry large or windowed data.
- RPC carries descriptors and commands, not bulk payloads.
- Zustand stores references and facts, not bytes or parsed render payloads.
- App demand policy owns app-specific demand intent derivation. Generic
  `DemandScheduler` owns lane ordering. Generic `ResourceExecutor` owns
  concurrency, retry/abort, stale completion drops, and backpressure.
- Pierre owns rendering/runtime behavior and exposes observations, not transport
  authority.
- DiffsHub is useful prior art for batching, tree/code decoupling, stable IDs,
  and virtualized imperative rendering, but not for Bridge's live viewport-first
  scheduler.
- Projection materialization is application-specific. Generic Bridge carries
  transport pathways; Review and Worktree/File Surface own frame semantics and
  materialization.
- Scheduling is split: app demand policy maps app meaning to generic lanes;
  generic demand scheduling orders lanes; generic resource execution enforces
  bounded execution and backpressure.
- Changeset remains a product/viewer lens. The stable Review protocol vocabulary
  is snapshot, delta, invalidation, package identity, generation, and revision.
- Current Bridge Review is stale-safe but coarse: CodeView remounts on revision,
  selected/visible hydration clears broadly, trees can reuse, and native
  invalidation facts are not yet consumed as a browser invalidation pipeline.
- Review source subscription is app-level over Bridge. The Review provider
  computes/materializes comparisons; the browser applies package lineage,
  schedules content, and renders.
- Worktree source subscription is app-level over Bridge. It materializes a
  live worktree as tree/status/file facts without instantiating Review package
  lineage.

## Main unresolved choices

- First continuous stream carrier in WKWebView.
- Exact per-lane content-fetch concurrency and byte/work budgets.
- Projection-order versus package-order selected neighborhood.
- First chunk/range integrity model.
- Whether producer-side stream windows are first implementation or follow-up.
- Whether native content resources should carry revision or remain generation +
  handle/hash scoped.
- Whether `invalidateContent` becomes first-class web invalidation or stays
  descriptor/key replacement.
- Whether a live changeset guarantees one stable package id across refreshes.
- Whether Pierre will expose a first-class visible-item observer so Bridge can
  stop depending on raw instance/DOM details.
- Whether Worktree tree-window frames are carried directly on intake or fetched
  as bounded resource windows from descriptors.
- Whether Worktree/File Surface open-file content should support any future
  automatic refresh cases beyond the first implementation's stale marker plus
  user refresh.
- Whether Worktree status patches include only summary/per-path status or also
  branch/ahead/behind metadata.

## Output artifacts

- Research ledger:
  `tmp/research-workflows/2026-06-22-bridge-transport-streaming-spec/research-ledger.md`
- Spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
- Review protocol spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md`
- Worktree/File Surface protocol spec:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- Accepted lane notes:
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/lanes/current-materialization-invalidation.md`
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/lanes/pierre-renderer-contract.md`
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/lanes/changeset-intake-model.md`
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/lanes/review-source-subscription-contract.md`
  `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/lanes/worktree-source-subscription-contract.md`
