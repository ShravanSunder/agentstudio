# Markdown retention correction

The File viewer now retains its last complete same-path Markdown presentation
while replacement content or rendering is pending. Returning to an unchanged,
completed render intent does not recreate the document. Changed selection and
superseded-result checks remain active; no new transport or recovery system was
introduced.

## Proof

- Real Vite/Swift RED: both mode round-trip and content refresh reached ready
  Markdown/Mermaid but lost 900 pixels of scroll position.
- Same E2E GREEN: 2 tests passed, exit 0, retaining the offset after both paths.
- Controlled hook Browser tests: 2 passed, covering retained content, unchanged
  activation, pending replacement, stale completion and selection revisit.
- Existing File Markdown Browser tests passed in the focused six-file run.
- Full TypeScript and exact owned-file formatting/type-aware lint passed.

Logs remain in
`tmp/debug-workflows/2026-09-06-pr-a-interaction-projection-rejections/`:
`markdown-scroll-retention-first.txt`, `markdown-scroll-green-first.txt`,
`browser-five-green-first.txt`, and `browser-three-green-third.txt`.
These are working-candidate proofs, not final integrated-main or PR-ready proof.

## Remaining work

The separate native Markdown-loading symptom needs fresh native readback.
The dev-server comparison-unavailable banner is a real failed backend attempt,
with its exact failure reason still unproven. Browser failure corrections outside
Markdown require the combined integration/aggregate gate. AgentStudio-Git/main
reconciliation follows current-worktree checkpoints and independent review.
