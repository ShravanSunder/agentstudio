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
   - app-hosted Bridge route boots through native host
   - protocol/source/resource identity agrees with browser surface
   - visible product checks, interaction assertions, stale/refresh where
     applicable, screenshots, scroll canaries, and negative-substitute checks
     are included
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

## Non-Goals

- Merge.
- Force-push or destructive git operations.
- Weakening proof gates to make the branch look green.

phase_result: complete
evidence: Gate 4 ticket drafted with PR-ready non-merge proof gates.
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: Gate 4 has a reviewable implementation ticket.
