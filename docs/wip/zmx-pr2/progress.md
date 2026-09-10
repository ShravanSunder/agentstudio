# PR2: zmx-only upgrade

Current owner decision: abandon the experimental Ghostty snapshot after reported
black flashes and tab-switch stutter under agent output. No obvious fix proven.
Keep embedded Ghostty at stable1.3.1 (332b2aef), unchanged from main.
Keep zmx upstream0.8.1 (8bab1f01), with task-scoped Zig0.16. Ghostty uses Zig0.15.2.
No new vendor source patches or vendor-repository commits.

- Old-daemon/new-client list/history/PTY attach/resize passed in isolated fixtures.
- zmx-only initial setup and72focusedtests passed before the Ghostty experiment.
- Ghostty trial and clipboard/packaging changes reverted by owner direction.
- Beta51 contains the abandoned experimental snapshot; not the zmx-only state.
- DraftPR338 stays unmerged. No CI/release watching requested.
- Restore stable debug build, verify focused tests, then update PR with reduced scope.

For restoration, reuse the primary checkout's prepared stable Ghostty framework
and resources after checking its pin/header. Keep this worktree's locally built
zmx0.8.1. This avoids editing Ghostty source to rebuild identical prepared inputs.
