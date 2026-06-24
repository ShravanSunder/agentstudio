You are continuing an implementation handoff.

Repo: `/Users/shravansunder/Documents/dev/project-dev/agent-studio.bridge-start`
Branch/worktree: `luna-338-pierreshikitrees-review-viewer-2`
Stage: post-review
Head at handoff: `41524ddecd1f06d537290880161b714bf95728e7`

Objective:
Continue the goal-backed Bridge Transport Streaming implementation. Ticket 04
Worktree/File browser surface review is clean and committed. Do not mark the
overall goal complete. Proceed to Ticket 05 hard-cutover cleanup, then final
implementation review and PR readiness.

Required workflow skill:
`shravan-dev-workflow:orchestrator-goal`

Current workflow:
`shravan-dev-workflow:implementation-execute-plan`

Next workflow:
`shravan-dev-workflow:implementation-execute-plan`

Terminal condition:
PR opened/updated and proven ready; do not merge unless separately authorized.

Required reading:
- `tmp/review-handoffs/2026-06-24-bridge-transport-ticket-04-to-ticket-05-handoff/implementation-handoff.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/spec.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/review-protocol.md`
- `tmp/spec-workflows/2026-06-22-bridge-transport-streaming-spec/worktree-file-surface-protocol.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-plan.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/file-organization.md`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/slices/05-hard-cutover-cleanup.md`
- `tmp/workflow-state/2026-06-22-bridge-transport-streaming/details.md`
- `tmp/workflow-state/2026-06-22-bridge-transport-streaming/events.jsonl`
- `tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/implementation-review-ticket-04-review-fix/report.md`

Current state:
- Branch was clean and ahead of origin by 28 at handoff creation.
- Latest commit was `41524dde Record ticket 04 final review transition`.
- Latest workflow event routes from
  `shravan-dev-workflow:implementation-review-swarm` to
  `shravan-dev-workflow:implementation-execute-plan`.
- Ticket 04 final re-review had two clean lanes:
  proof closure no findings, high confidence; security/trust-boundary no
  findings, high confidence.

Do not redo:
- Do not reopen Ticket 04 unless current code diverges from this handoff.
- Do not re-litigate the closed-app HMAC/encryption decision; it is deferred
  hardening, not a Ticket 05 gate.
- Do not broaden cleanup into unrelated repo-health fixes unless the failure is
  inside Ticket 05 write scope.

Next action:
Execute Ticket 05 hard-cutover cleanup from
`tmp/plan-workflows/2026-06-22-bridge-transport-streaming-implementation-plan/slices/05-hard-cutover-cleanup.md`.

Ticket 05 first checkpoint:
1. Reconfirm `git status --short --branch`, `git rev-parse HEAD`, and the latest
   event in `events.jsonl`.
2. Add or identify red proof for cleanup boundaries before deleting or moving
   compatibility paths:
   - generic `BridgeWeb/src/core/**` cannot import Review/Worktree/File app
     modules, `review-viewer`, or `foundation/review-package`
   - no app protocol fetches by raw descriptor string or raw resource URL
     authority
   - Zustand snapshots contain refs/status/facts only, not bodies/promises/
     controllers/workers/Pierre instances
   - comments/comms resource kinds and flags stay rejected/disabled
   - telemetry canary rejects raw paths, source text, prompts, capability URLs,
     comments, comms, and handles
   - Worktree dev route no longer depends on Review package fabrication
3. Implement cleanup narrowly.
4. Run required proof gates from slice 05.
5. Commit verified checkpoint(s).
6. Run final `shravan-dev-workflow:implementation-review-swarm`, then
   `shravan-dev-workflow:implementation-pr-wrapup`.

Constraints:
- Stay within the listed write scope.
- Verify claims against current files before editing.
- Use TDD for behavior changes and do not weaken proof lanes.
- Use Zod v4 for schema-shaped metadata/data. Avoid `any`, casual casts, and
  hidden `JSON.parse` paths.
- Large bodies stay out of Zustand; store refs/status/facts only.
- If cleanup seems to require keeping old and new fetch authority paths alive in
  the same protocol, stop and report the design contradiction.

Return:
- What changed
- Commands/tests run with exit codes
- Remaining blockers or risks

This is a manual handoff prompt. Do not assume access to previous chat. If any
referenced file is missing or branch state differs, stop and report the mismatch
before reviewing or editing.
