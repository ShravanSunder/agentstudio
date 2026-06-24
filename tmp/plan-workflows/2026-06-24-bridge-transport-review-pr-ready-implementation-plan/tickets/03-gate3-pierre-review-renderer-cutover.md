# Ticket 03: Gate 3 Pierre/Review Renderer Cutover

Status: draft for plan-review-swarm
Depends on: Tickets 00-02

## Deliverable

Move Review/Pierre rendering onto the new transport/materialization/scheduler
model. PR-ready requires hard cutover for every in-scope renderer entry path.

The old renderer/remount path may not remain reachable for covered routes.

## Reviewer Reminder

Review this ticket against the prior false-green failure mode. Ask whether the
new transport path can pass while a covered user-visible route still reaches the
legacy renderer/remount bypass or loses DiffsHub-like scroll stability.

## Vertical Slices

1. Renderer adapter contract
   - renderer receives prepared app/protocol data, not Bridge URLs or generic
     transport descriptors
   - unit proof for adapter input shape

2. Static diff path
   - DiffsHub-like static diff smoothness
   - stable extent facts consumed before body hydration

3. Live update path
   - same-lineage updates avoid full remount
   - stale completions rejected

4. Change-set comparison path
   - live/closed/pinned comparisons render through new path
   - source/version changes reset intentionally

5. Legacy bypass negative proof
   - covered routes cannot reach the legacy renderer/remount path
   - failing assertion if bypass remains reachable

## Proof Gates

Required:

- unit tests for adapter contracts
- browser/integration tests for static diff, live update, and change-set paths
- scroll canary for large tree/diff/file content
- performance/telemetry proof where required by the spec
- implementation review focused on renderer hard cutover

phase_result: complete
evidence: Gate 3 ticket drafted with hard-cutover and negative-bypass proof.
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: Gate 3 has a reviewable implementation ticket.
