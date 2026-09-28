# Worktree CLI: what it needs and why

Date: 2026-09-27. Owner: workspace-control (Claude 6b0a29fc). Authority: the
owner's direction relayed by the Worktrees orchestrator (9304749a) and the
owner's own words on 2026-09-27, quoted below.

## The problem

Agent Studio can already make an APFS copy-on-write fork of a worktree, or a
clean worktree from the default branch, using agentstudio-git (#363). Only the
app's command bar can do it. Agents and people in terminals fall back to `git
worktree add` or a full clone, which costs disk and time.

Owner, relayed 2026-09-26: make it so "any CLI can use our system to fork",
because forks save disk, and "we need that in main soon so that it's in the
next release."

Owner, 2026-09-27:
- "we dont want permissions and systems right now … its like wt worktrunk
  anyone can make it";
- "its just a command that anyone can call as its just a cli command like wt";
- "we are using agentstudio-git primitives, same as the app";
- chose "the CLI does it itself" over "through the app".

`wt` is the model for how it behaves. The tool itself isn't used.

## Who it's for

Anyone at a terminal: an agent in an Agent Studio pane, or a person in any
terminal. The app doesn't need to be running.

## The needs

| # | Need | Why | Priority |
| --- | --- | --- | --- |
| W1 | `agentstudio worktree new <branch>` creates a worktree on a new branch from the repository's default start point, using the same agentstudio-git call and naming as the command bar's "From Default". | A clean branch in one command. | Must |
| W2 | `agentstudio worktree fork <branch>` makes an APFS copy-on-write fork of a worktree onto a new branch, using the same agentstudio-git fork as the command bar's "Fork". The source is the worktree the command runs in, unless one is named. | Saves disk and keeps build outputs warm. The owner's reason for the work. | Must |
| W3 | Both return when the worktree exists on disk, and print its path and branch. A failure says what went wrong in terms a person or agent can act on. | The next command can `cd` into it. | Must |
| W4 | `agentstudio worktree list` prints the repository's worktrees with path and branch. | Replaces `wt list` / `git worktree list`. | Must |
| W5 | No permissions, credentials, app connection or IPC. It works from any terminal, with the app open or closed. | Owner: "not tied to anything". | Must |
| W6 | A worktree made this way shows up in Agent Studio the same way any worktree on disk does, when its folder is watched. | One source of truth: the disk. | Must |
| W7 | It ships in the stable and beta apps' bundled CLI. | The next release. | Must |

## Not in this change

- `worktree remove`: deleting needs its own safety rules. The SDK has
  `removeWorktree`; this is the next design.
- A shell hook to `cd` the caller's shell: the printed path covers it.
- Hiding a fork from the app's scanner while it is being built. The SDK
  builds at the final path; an SDK "stage then move" is a follow-up in
  agentstudio-git.
- "From Branch…" (a clean worktree from an arbitrary branch).
