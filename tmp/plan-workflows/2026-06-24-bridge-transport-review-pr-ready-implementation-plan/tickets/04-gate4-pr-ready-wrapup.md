# Ticket 04: Gate 4 PR-Ready Non-Merge Wrapup

Status: draft for plan-review-swarm
Depends on: Tickets 00-03

## Deliverable

Make the branch PR-ready but do not merge.

## Reviewer Reminder

Review this ticket against the prior false-green failure mode. Ask whether PR
checks, Vite proof, or native markers can pass while the visible product remains
wrong. PR-ready requires visible product proof and native Agent Studio
Bridge/WKWebView proof, not only green lower-layer checks.

## Required Proof

1. Dev-server/browser product proof
   - Gate 0 proof still passes
   - Review/Pierre browser proof passes

2. Native Agent Studio Bridge/WKWebView proof
   - Worktree/File native route boots through native host
   - Review/Pierre native route boots through native host
   - in-scope change-set/native comparison route boots when included by Gate 3
   - protocol/source/resource identity agrees with each browser surface
   - visible product checks, interaction assertions, stale/refresh where
     applicable, screenshots, scroll canaries, and negative-substitute checks
     are included
   - Ticket 03 legacy-bypass negative assertion is rerun for native covered
     routes
   - Victoria/log markers correlate route boot, event stream readiness, and
     resource/content requests

3. Performance/observability proof
   - queue depth, in-flight work, stale drops, aborts, content latency, stream
     gaps/resets, and scroll canaries are marker-correlated where required

4. Quality proof
   - focused unit/integration/browser tests pass
   - `pnpm --dir BridgeWeb run check`
   - `mise run lint`
   - broader repo tests as required by touched scope

5. Review and PR state
   - implementation-review-swarm completed
   - accepted findings addressed or explicitly rejected
   - PR opened or updated
   - checks, review comments, and mergeability freshly reported

## Native Proof Artifact Requirements

Native proof must produce inspectable artifacts, not only command success:

- exact native route or scenario identifier for every covered surface
- app bundle identity and launch method
- marker id used for Victoria/log correlation
- page/host handshake facts
- protocol/source/resource identity facts
- event stream ready marker and resource/content request markers
- visible product assertions and screenshots for each surface
- scroll canary and stale/refresh evidence where applicable
- negative-substitute and legacy-bypass assertions

## Required Commands

```bash
pnpm --dir BridgeWeb run test
pnpm --dir BridgeWeb run test:browser:integration
pnpm --dir BridgeWeb run test:dev-server:worktree
pnpm --dir BridgeWeb run test:benchmark:browser
pnpm --dir BridgeWeb run check
mise run observability:up
mise run run-debug-observability -- --detach
mise run verify-debug-observability
mise run verify-bridge-observability
mise run bridge-web-browser-benchmark
mise run lint
mise run test
```

## Non-Goals

- Merge.
- Force-push or destructive git operations.
- Weakening proof gates to make the branch look green.

phase_result: complete
evidence: Gate 4 ticket drafted with PR-ready non-merge proof gates.
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: Gate 4 has a reviewable implementation ticket.
