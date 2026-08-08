# Git trigger and status hotspot

## Source-backed path

```text
Darwin FSEvent stream
  → FilesystemActor path routing/filtering
  → per-worktree 500 ms quiet debounce / 10 s ceiling
  → RuntimeEnvelope.filesChanged
  → GitWorkingDirectoryProjector pending changeset
  → up to four admitted status tasks
  → @concurrent / detached libgit2 status
  → equal snapshot dedup or Git event publication
```

The trigger classes are:

- registration/topology hydration, which eagerly admits an initial full status;
- ordinary projected file changes, which can use pathspec status for small safe sets;
- `.git` changes, which force full status;
- immediate activity, active-pane, visible-sidebar, watched-folder, or explicit refresh hints;
- a 15-second active/visible self-heal tick and slower background stripes;
- capacity, timeout, cancellation, SDK, or in-flight retries.

Sources: [FilesystemActor.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Core/RuntimeEventSystem/Filesystem/FilesystemActor.swift:274), [GitWorkingDirectoryProjector.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector.swift:546), and [GitWorkingDirectoryProjector+PathspecStatus.swift](/Users/shravansunder/Documents/dev/project-dev/agent-studio.slowdonw/Sources/AgentStudio/Core/RuntimeEventSystem/Git/GitWorkingDirectoryProjector+PathspecStatus.swift:71).

## Production evidence

The trailing production window recorded approximately 79–93 status scans in two minutes, with 76–83 periodic tick enqueues. The successful scans were almost entirely full status. The same window recorded an equal number of snapshot deduplications and zero Git events published.

The measured full-status wall time was approximately 89–108 ms average, 488–511 ms p95, and 1,034 ms maximum. The unfiltered stack sample found 1,107/5,209 intervals in `LibGit2StatusReader.status` / `git_status_list_new`, including index-to-worktree diff and submodule traversal.

This is CPU pressure even when the downstream Git UI remains unchanged: deduplication happens after the native scan.

A later current-channel rollup (30 minutes, generic stable marker `trace`, not PID-bound) recorded 742 successful statuses, 647 full and 35 pathspec; 502 unavailable attempts (309 capacity, 164 timeout, 29 already-in-flight); 738 snapshot deduplications; and 4 event-posted records. Successful status elapsed time averaged about 224 ms, p50 about 114 ms, p95 about 823 ms, and max about 1,397 ms. The hash-grouped counts were concentrated in a few worktrees, with `acdb0ed8bf7bfb00` at 69 admissions/52 statuses and `809c4428faf0d071` at 44 admissions/17 statuses. Because the channel marker has no process identity, this rollup is corroboration of current Git pressure, not a PID-specific causal join. The detailed rollup is [09-fresh-production-and-beta.md](09-fresh-production-and-beta.md).

## Coalescing and gaps

Working coalescing exists at several layers: per-worktree path sets, one pending changeset, a 500 ms projector window, four admission slots, retry/deferred slots, snapshot equality suppression, and a 16 ms cache accumulator. It does not prevent periodic unchanged full scans from reaching libgit2. FSEvent ingress is unbounded, and capacity retries are fixed at roughly 500–600 ms.

`suppressed_ignored_path.max=6,791` indicates heavy watcher/filter ingress, not 6,791 Git scans; ignored-only paths are accumulated until a qualifying event.

## MainActor edge

Status computation is off-main. Raw `filesChanged` envelopes still reach `WorkspaceSurfaceCoordinator` on MainActor, and `WorkspaceCacheCoordinator` can receive a no-op consume hop even when the eventual Git snapshot is deduplicated. Git snapshot publication was zero in the trailing window, so Git cache/UI mutation is not the direct cause of that CPU sample.

## State

`accepted` — recurring Git full-status work is the highest-confidence product CPU hotspot. The exact dominant trigger class by worktree (periodic versus FSEvent re-arm versus immediate hint) remains `unresolved`; group by worktree hash and 10-second bucket in a fresh workload capture.
