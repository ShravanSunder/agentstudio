# Ticket 03: Gate 3 Pierre Renderer Cutover For ReviewViewer And FileViewer

Status: draft for plan-review-swarm
Depends on: Tickets 00-02

## Deliverable

Move ReviewViewer and FileViewer rendering onto the new
transport/materialization/scheduler model. PR-ready requires hard cutover for
every in-scope renderer entry path.

The old renderer/remount path and the standalone `WorktreeFileApp`/raw `<pre>`
path may not remain reachable for covered routes.

## Reviewer Reminder

Review this ticket against the prior false-green failure mode. Ask whether the
new transport path can pass while a covered user-visible route still reaches the
legacy renderer/remount bypass, the standalone worktree file viewer, raw file
rendering, or loses DiffsHub-like scroll stability.

## Vertical Slices

1. Renderer adapter contract
   - renderer receives prepared app/protocol data, not Bridge URLs or generic
     transport descriptors
   - FileViewer receives Pierre `file` items and ReviewViewer receives Pierre
     `diff`/`file` items through the same CodeView path where applicable
   - unit proof for adapter input shape

2. FileViewer file path
   - opened worktree files render through Pierre CodeView/File
   - Shiki and worker-backed highlighting are active when `workers=on`
   - raw `<pre>` body rendering is a failing substitute

3. Static diff path
   - DiffsHub-like static diff smoothness
   - stable extent facts consumed before body hydration

4. Live update path
   - same-lineage updates avoid full remount
   - stale completions rejected

5. Change-set comparison path
   - live/closed/pinned comparisons render through new path
   - source/version changes reset intentionally

6. Legacy bypass negative proof
   - covered routes cannot reach the legacy renderer/remount path
   - covered routes cannot reach standalone `WorktreeFileApp`
   - failing assertion if bypass remains reachable

## Proof Gates

Required:

- unit tests for adapter contracts
- browser/integration tests for FileViewer file, static diff, live update, and
  change-set paths
- scroll canary for large tree/diff/file content
- performance/telemetry proof where required by the spec
- implementation review focused on renderer hard cutover
- Gate 0.a current-worktree shared FileViewer/Pierre product proof remains green
  before this ticket closes

## Required Commands

Standing Gate 0.a regression command consumed from Ticket 00:

```bash
pnpm --dir BridgeWeb run test:dev-server:worktree
```

```bash
pnpm --dir BridgeWeb run test -- <focused renderer/materialization tests>
pnpm --dir BridgeWeb run test:browser:integration -- <focused renderer browser tests>
pnpm --dir BridgeWeb run test:benchmark:browser
pnpm --dir BridgeWeb run check
pnpm --dir BridgeWeb run test:dev-server:worktree
mise run bridge-web-browser-benchmark
mise run lint
```

phase_result: complete
evidence: Gate 3 ticket drafted with hard-cutover and negative-bypass proof.
recommended_next_workflow: shravan-dev-workflow:plan-review-swarm
recommended_transition_reason: Gate 3 has a reviewable implementation ticket.
