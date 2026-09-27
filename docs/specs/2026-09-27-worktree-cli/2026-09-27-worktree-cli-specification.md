# Worktree CLI: what must be true

Date: 2026-09-27, revision 3 (supported layouts; leftovers instead of "change started"). Revision 2 (review: discovery from nested folders, a total
result contract, typed cleanup, no app-timing guarantee). Serves
[the Requirements](2026-09-27-worktree-cli-requirements.md) (W1–W7).

## Things

| Id | Thing | Same when | Always true |
| --- | --- | --- | --- |
| E1 | Repository | same Git common directory | found from the worktree that contains the current directory (or `--repo <path>`), from any folder inside it |
| E2 | Worktree | same canonical root path | belongs to one E1; the "current worktree" is the one containing the current directory, found from any folder inside it |
| E3 | Destination | same path | the sibling folder `<parent of E1's main worktree>/<main worktree folder>.<branch slug>`, named by the same rule the command bar uses; must not exist |
| E4 | Outcome | one per call | exactly one of: **created**, **listed**, **refused** (nothing on disk changed, proven before any change), **failed** (an operation failed; says what is known about anything it left on disk) |
| E5 | Leftovers | one per failed call | **notNeeded** (a read failed before anything was attempted), **noLeftovers** (the fork left nothing: it failed before changing anything, or agentstudio-git undid every change, as its fork contract guarantees unless it reports leftovers), **incomplete** (agentstudio-git reports typed leftovers), **unverified** (agentstudio-git gives no evidence either way, as for `new`) |
| E6 | Supported layout | — | for `new` and `fork`: a repository whose main worktree agentstudio-git reports, since the destination is named after it. Repositories where it reports none (a separate Git directory, a submodule) are outside this change's supported layouts. `list` has no such limit |

## Surface

```text
agentstudio worktree new  <branch> [--repo <path>] [--json]
agentstudio worktree fork <branch> [--from <path>] [--json]
agentstudio worktree list [--repo <path>] [--json]
```

These run inside the CLI process through agentstudio-git. They open no socket
and read no credential. `--repo` and `--from` accept any folder inside a
worktree, like the current directory.

## Rules

| Rule | What must be true | Needs |
| --- | --- | --- |
| WR1 | `new` finds E1 (from the current directory or `--repo`, at any depth inside a worktree), resolves the default start point exactly as the command bar does (origin's HEAD, else local `main`, else `master`; no fetch), and creates E3 on the new branch through agentstudio-git. | W1 |
| WR2 | `fork` uses as its source the worktree containing the current directory (or `--from`), main or linked, at any depth inside it, and forks **that** worktree, never a different checkout of the same repository. It creates E3 through agentstudio-git's fork on the new branch at the source's HEAD, carrying uncommitted, untracked and ignored files the way the command bar's fork does. | W2 |
| WR3 | **created**: one human line `created <branch> at <absolute path>`; `--json` prints `{"outcome":"created","operation":"new"\|"fork","branch","path","repository","materialization"?}`. Exit 0. | W3 |
| WR4 | **refused**: nothing on disk changed. The reason comes from a closed set: `notInRepository`, `notInWorktree`, `noDefaultBranch`, `invalidBranchName`, `emptyBranchSlug`, `branchAlreadyExists`, `destinationExists`, `destinationParentMissing`, `unsupportedRepositoryLayout` (`new` and `fork` only, E6), and `forkUnavailable` (carrying the SDK's typed pre-mutation rejection reason). Human: `refused: <reason> …`; `--json`: `{"outcome":"refused","reason","path"?,"detail"?}`. Exit 1. | W3 |
| WR5 | **failed**: an operation failed after preflight. It reports the failure's typed kind and its useful detail (for example the entry's relative path and reason, or the Git error kind, never raw Git or libgit2 text), and E5 leftovers. A fork failure reports `noLeftovers`, or `incomplete` with each leftover's kind and location **as agentstudio-git types it** (content relative to the destination, administration relative to the repository's Git directory, or a branch reference); it makes no claim about whether a change had started. A `new` failure reports `unverified`. A read failure reports `notNeeded`. `--json`: `{"outcome":"failed","failure":{kind, detail…},"leftovers":{"status", "items"?:[{kind, location, base}]}}`. Exit 2. | W3 |
| WR6 | **listed**: each worktree of E1 with its path, branch (or `detached`), and whether it is the main worktree. Human: one line per worktree; `--json`: `{"outcome":"listed","repository","worktrees":[{"path","branch"?,"isMain"}]}`. Exit 0. A repository it can't find is refused `notInRepository`; a read failure is failed with cleanup `notNeeded`. | W4 |
| WR7 | No command opens the app's socket, reads a pane token, or needs the app to run. They behave the same from Terminal.app and from an Agent Studio pane. | W5 |
| WR8 | A successful return means the worktree is complete on disk. It doesn't mean the app has shown it: a running app shows it through its normal discovery, some time after. The app may see a fork partway while it is being built; a rolled-back fork disappears through discovery the same way. | W6 |
| WR9 | The commands are in the CLI bundled with stable and beta builds. | W7 |

## Proof

| Rules | Evidence |
| --- | --- |
| WR1, WR2 | Integration against temporary repositories: the repository root and a nested folder, in both the main and a linked worktree, plus explicit `--repo` / `--from`; a fork from a linked worktree copies that worktree's files, not the main checkout's |
| WR3–WR6 | A contract table test for every reachable typed outcome (each refusal including `unsupportedRepositoryLayout`, a read failure → `notNeeded`, a fork cancellation or entry failure → `noLeftovers`, a fork cleanupIncomplete with each residue kind, a `new` failure → `unverified`); CLI golden output for human and `--json` shapes and exit codes of created, listed, refused and failed |
| WR7 | A test through the real top-level dispatch that runs a successful `worktree` command and observes that the IPC client and credential reading are never entered |
| WR8, WR9 | A packaged-app smoke: the bundled `agentstudio worktree fork` from a pane in a watched repository; the sidebar eventually shows the fork |
