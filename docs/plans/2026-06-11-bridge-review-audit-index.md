# 2026-06-11 Bridge Review Foundation Audit — Plan Index

Planned at: 578c1084 (branch `bridge-start`, "Build Bridge review foundation")
Audit method: 4 parallel read-only lanes (Swift spec-drift, WebKit trust
boundary, BridgeWeb scaffold, docs reconciliation) + parent verification of
every accepted finding against source, plus baseline test runs.

Authority chain audited and confirmed healthy:
spec `docs/superpowers/specs/2026-06-10-bridge-review-foundation.md` (canonical)
→ master plan `docs/plans/2026-06-08-bridge-agent-review-foundation.md`
→ retired `docs/plans/2026-02-23-bridge-diff-execution-plan.md` (proper tombstone)
→ sibling git data-plane plan (ownership boundary language clean; its own
readiness is a separate, known-blocked lane).

## Baseline evidence (parent-run, 2026-06-11)

- BridgeWeb: `pnpm run check` exit 0; `pnpm run test` exit 0 (9 files,
  10 tests).
- Swift: `mise run test -- --filter Bridge` exit 0 (incl. WebKit serialized
  suites).
- Vocabulary bans hold in code: zero `BridgeDiff*`/`DiffManifest`/
  `resource/file/{fileId}?epoch` references in Sources/ or Tests/.

## Plans (dependency/priority order)

| Status | Plan | Why now | Primary proof |
| --- | --- | --- | --- |
| proposed | [bridge-lazy-content-cutover](2026-06-11-bridge-lazy-content-cutover.md) | Pipeline eagerly loads every handle's bytes before publishing a package — the exact gap the spec names; blocks large-diff viability and owns cancellation/staleness at the boundary | zero-loadContent-during-loadPackage test; single-flight + stale-rejection tests |
| proposed | [bridge-foundation-production-wiring](2026-06-11-bridge-foundation-production-wiring.md) | Pipeline/provider/change-index are test-only; `loadDiff` still stats-only — the foundation is unreachable in production; must not block on the not-ready git lane (injectable provider seam) | package-publication controller test; provider-unavailable typed failure |
| proposed | [bridgeweb-transport-ci-and-shell-proof](2026-06-11-bridgeweb-transport-ci-and-shell-proof.md) | No push receiver / RPC client / nonce consumption in BridgeWeb; CI runs zero BridgeWeb steps; fixtures (5 of 16) have no sync mechanism; master-plan Task 9 shell proof unchecked | CI red-on-injected-error check; shell renders pushed package; packaged WebKit smoke |
| proposed | [bridge-delta-live-refresh](2026-06-11-bridge-delta-live-refresh.md) | `BridgeReviewDeltaBuilder` missing; `BridgeChangeIndex` unfed and provider-less — packages go stale on first file change; TS delta consumer already exists | rebuild-equivalence property test; fact→delta envelope test |
| proposed | [bridge-trust-boundary-hardening-tests](2026-06-11-bridge-trust-boundary-hardening-tests.md) | Scheme-task cancellation not wired (abandoned loads run to completion); symlink confinement implicit/untested; negative/overflow generation, unknown-handle, pre-ready rejections untested | cancellation test with slow fake; symlink-escape fixture test |
| proposed | [bridge-architecture-doc-reconciliation](2026-06-11-bridge-architecture-doc-reconciliation.md) | Architecture doc teaches retired `DiffManifest` in 11 places incl. a code sample for a nonexistent type; Task 0 doc-update debt; misleads LUNA-338 onboarding | `grep -c DiffManifest` → 0; samples name only real types |

Sequencing: lazy-content → production-wiring → delta-live-refresh form the
dependency spine. BridgeWeb CI/fixture tasks, hardening tests, and the doc
reconciliation are independent and can run in parallel with the spine.

## Recommended next skill per plan

- Pre-execution adversarial review (recommended for lazy-content and
  production-wiring — they touch the content trust path and the RPC surface):
  `plan-review-swarm`.
- Execute: `implementation-execute-plan` (each plan embeds its handoff
  prompt).

## Verified-healthy (do not re-audit)

- Vocabulary cutover in code (Task 0/1/2 claims spot-verified honest).
- Actor isolation: pipeline/index/store/provider are non-MainActor actors;
  Sendable DTOs; no blocking I/O in nonisolated async paths found.
- `BridgeContentStore` keying (handle+generation+item+role+endpoint+hash) —
  base/head collision protection tested.
- Time-window collation creates no canonical checkpoint (pure collator).
- Scheme handler: stable percent-decode before segment-based traversal check;
  unknown-host rejection; strict generation parsing (missing/empty/
  malformed/negative/overflow all return nil) — tests exist for traversal and
  unknown-host; remaining untested paths are owned by the hardening plan.
- Navigation allowlist (agentstudio/about internal, http/https external,
  rest blocked) with tests.
- Nonces: per-controller `UUID().uuidString`
  (`BridgePaneController.swift:131-132`); `isBridgeReady` set-once-per-load,
  reset on teardown (`:45,369-400`).
- Git data-plane plan boundary: explicitly disclaims Bridge contracts,
  BridgeWeb shapes, content handles, URLs, checkpoint semantics, and
  generation vocabulary (its execution readiness is a separate lane —
  2026-06-10 review swarm verdict not_ready stands).
- BridgeWeb scaffold quality: strict tsconfig + oxlint, exact TS↔Swift
  contract field parity (spot-diffed), compliant domain folder shape and test
  naming, no generic filenames.

## Claims investigated and REJECTED (do not re-fix)

- "Content server missing generation guard" — `BridgeContentStore.load`
  enforces generation equality and unknown-handle rejection; guard exists.
- "Nonce source unknown/possibly static" — resolved: fresh UUIDs at
  controller setup.
- "Bridge-ready gating unverified" — resolved: set-once + reset lifecycle is
  correct in `BridgePaneController`.
- "App assets could escape via symlink" — current code is safe
  (standardize-resolves-then-prefix-check); the residual item is a *test +
  intent comment*, owned by the hardening plan, not a live vulnerability.
- "MIME inference unsafe" — packaged-assets-only context; octet-stream
  default; no action.
