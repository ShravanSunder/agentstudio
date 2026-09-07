# Transport regression-proof checkpoint

This checkpoint preserves the permanent sustained File refresh witness and its
frame-based visible-content observation helper. It changes no production code.

The witness performs sixteen distinct same-line-count filesystem edits through
the real Vite/Swift backend. Each successor must reach its exact painted SHA;
scroll position, visible content and zero page errors are asserted. Fixture
resources are closed through the established cleanup harness.

## Observed proof

Tested against `64c8081b4` plus the shared working candidate, not an isolated clean
commit. Production reliability changes still uncommitted are not included in
this checkpoint, so this is not a claim that the committed branch alone passes.

- `mise run test:bridge-web:e2e:ordinary -- tests/e2e/bridge-viewer-vite-sustained-file-refresh.e2e.test.ts`:
  1 test passed, exit 0; final run includes all sixteen successors and zero page errors.
- Exact test formatting, type-aware lint and full BridgeWeb TypeScript check:
  exit 0.
- Evidence: `tmp/debug-workflows/2026-09-06-pr-a-interaction-projection-rejections/sustained-file-refresh-final.txt`.

## Remaining failures and dependencies

- The ring-buffer production correction remains uncommitted in a file also
  containing reconnect changes. It needs a dependency-complete checkpoint.
- The duplex integration fixture correction depends on the uncommitted canonical
  annotation receipt contract. Its Node stage passed 22 tests, but it is not
  included here as a standalone fix.
- Browser integration: 5 failed, 359 passed, 6 skipped. Two failures involve
  Review item-kind consistency; three involve saved-comment presentation.
- Markdown scroll retention: two real-backend failures after mode switching and
  content refresh, despite exact document/diagram readiness. UI owner handoff is
  recorded in transport communications 0119–0121.
- A subsequent native Markdown revisit stayed loading. Content-versus-renderer
  ownership remains unresolved; earlier native smoke was sampled success only.
- Full aggregate, current-main/SDK integration, independent review, final pushed
  checks and packaged proof remain incomplete. PR #316 must remain unmerged.

No test was weakened, no timeout increased, and no source or user data was
discarded to create this checkpoint.
