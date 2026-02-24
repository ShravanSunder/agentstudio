# Sidebar Repo Metadata Grouping/Filtering Spec

## Goal
Use normalized per-repo metadata as the source for sidebar grouping, search, and filtering so users can pivot by repository identity, remotes, and filesystem structure without duplicate ambiguity.

## Metadata Contract (Per Repo)
Each `RepoIdentityMetadata` record is expected to carry:

1. `repoName` — canonical repo name (remote repo segment when available, otherwise local folder name).
2. `worktreeCommonDirectory` — resolved git common dir when available.
3. `folderCwd` — normalized repo folder cwd path.
4. `parentFolder` — immediate parent folder name for folder-level grouping.
5. `organizationName` — remote org/account (or nested org path) when available.
6. `originRemote` — raw `origin` URL when available.
7. `upstreamRemote` — raw `upstream` URL when available.
8. `lastPathComponent` — repo folder `lastPathComponent`.
9. `worktreeCwds` — normalized worktree cwd paths for this repo entry.
10. Existing fields preserved: `groupKey`, `displayName`, `remoteFingerprint`, `remoteSlug`.

## Display Rule
Group title format:
- Preferred: `repo · organization`
- Fallback: `lastPathComponent`

## Next-Phase Functional Requirements

### F1 — Grouping Facets
Support grouping by:
1. Repository identity (existing default).
2. Organization.
3. Parent folder.
4. Remote host/fingerprint.

### F2 — Filter Facets
Support filtering by:
1. Organization.
2. Parent folder.
3. Presence of upstream.
4. Presence of origin.
5. Worktree count ranges (e.g. `1`, `2-5`, `6+`).

### F3 — Search Index Inputs
Search should match against:
1. `displayName`
2. `repoName`
3. `organizationName`
4. `lastPathComponent`
5. `parentFolder`
6. `originRemote`
7. `upstreamRemote`
8. `folderCwd`
9. `worktreeCwds`

### F4 — Deterministic Ordering
Sorting should be stable and deterministic:
1. Group key/title ascending.
2. Repo/worktree display rows ascending by visible label.

### F5 — Missing Metadata Behavior
If metadata fields are unavailable, behavior must degrade gracefully:
1. No crashes.
2. Grouping/filtering falls back to path-based identity.
3. UI labels still render with local folder naming.

## Testing Plan (Phase 2)
1. Group-by facet tests (org, parent folder, remote, identity).
2. Filter facet tests (origin/upstream/org/parent/worktree count).
3. Search token coverage tests for all indexed fields.
4. Deterministic sort tests for mixed populated/missing metadata.
