# 2026-08-23 Review Epic Real-Worktree Chrome Proof

Status: in progress. This ledger separates current-source automated evidence from manual Chrome evidence against a disposable real Git worktree.

## Authority coverage

Fully read in this run:

- `docs/specs/2026-08-06-worktree-annotations/README.md`, lines 1-73.
- `pr0-user-requirements.md`, lines 1-274.
- `pr0-specification.md`, lines 1-599.
- `2026-08-10-pr0-review-comparison-basis.md`, lines 1-79.
- comparison-target-loading `user-requirements.md`, lines 1-147.
- comparison-target-loading `specification.md`, lines 1-294.
- `pr1-user-requirements.md`, lines 1-575.
- `pr1-specification.md`, lines 1-1368.
- latest-generation `2026-08-18-requirements.md`, lines 1-268.
- latest-generation `2026-08-18-specification.md`, lines 1-438.
- refresh-classification `2026-08-21-requirements.md`, lines 1-145.
- refresh-classification `2026-08-21-specification.md`, lines 1-349.
- Swift development-backend `user-requirements.md`, lines 1-138.
- Swift development-backend specification, lines 1-225.

PR2 vision/research is non-normative and excluded. Deprecated 2026-08-03 and 2026-07-30 artifacts are source material only and excluded.

## Runtime fixture

- Product source HEAD: `af7ffaf955c00ea0273d3bb66493b8603962c7b0`.
- Disposable repository root: `/tmp/agentstudio-review-real-worktree.C898DE/repository`.
- Seeded linked worktree: `/tmp/agentstudio-review-real-worktree.C898DE/review-worktree`.
- Feature HEAD: `6c3b3c4` (`feature/review`).
- Repository default: `origin/main` at `9aed48f`, advanced independently from fork `4d9ad09`.
- Real local states: committed additions/deletions, staged changes, unstaged changes, and an untracked file.
- Isolated Core/local data root: `/tmp/agentstudio-review-dev-data.hEcsvL`.
- Swift backend: `127.0.0.1:43872`; direct health `204`.
- Vite: `127.0.0.1:5175`; proxied backend health `204`.
- Chrome: installed and extension/native host valid, but not running or connected yet.

## Workflow ledger

Status vocabulary: `pending`, `pass`, `fail`, `blocked`, or `not-manually-inducible` with a separate automated proof anchor.

### A. Real development carrier and initial Review

1. Open Review through Vite with workers enabled; prove bootstrap, metadata, and content come from the isolated Swift backend for the exact seeded worktree. Authorities: Dev R1-R4, V1-V4; R-BLO-015/016.
2. Initial Review uses the repository-designated `origin/main`, identifies it as Default, and does not enumerate the branch catalog before the picker opens. Authorities: P0-R1; CT-R1.
3. Contribution excludes `Sources/TargetOnly.swift`, which exists only on advanced `origin/main`. Authorities: P0-R3; Scenario A.
4. Full-worktree Review includes feature commits plus staged, unstaged, deleted, and untracked state with truthful file status. Authorities: P0-R4; Scenario C.
5. Reload the complete browser document and prove the newest native-complete Review bootstraps and applies without losing the displayed result. Authorities: R-RRC-002/009; R-BLO-003.

### B. Comparison-target workflows

6. Open Compare Worktree; one on-demand query loads a bounded recent catalog, correct input receives focus, and switching Commit/Branch reuses the preload. Authorities: CT-R2-R5.
7. Search and select a distinguishable local or remote-tracking branch; current comparison and durable intent change only through selection. Authorities: P0-R2; CT-R4-R6.
8. Select Common commit and Branch tip basis and observe their distinct projections/current-state labels. Authority: accepted comparison-basis delta.
9. Enter and apply an exact commit; verify it is pinned and basis-free. Authorities: P0-R2/R5; accepted basis delta.
10. Close/cancel a picker query without changing the active comparison. Authorities: CT-R5/R7.
11. Restart the backend with the same data root; restore symbolic target intent, freshly resolve moved target truth, and never treat the old snapshot as current. Authorities: P0-R8/V4; Dev R5-R6.

### C. Inline annotation authoring and durability

12. Drag a range: paint and endpoint `+` appear without durable comment; outside click/Escape clears it. Single-line gutter `+` opens directly. Authority: R-P1-002.
13. Empty/whitespace composer disappears without durable state. First non-whitespace edit becomes a durable root draft; focus loss flushes; Escape/new range collapses; reload restores it. Authority: R-P1-003.
14. Save a root message; exact command receipt ends Saving immediately, the row never disappears, and projection convergence is separate. Command+Enter saves; Enter/Shift+Enter insert newlines. Authorities: R-P1-004/014; R-BLO-002.
15. Edit and Revert a saved message, including durable empty edit and first-character/editor continuity. Authority: R-P1-003/004/016.
16. Create and Save a second different message in the same session without unrelated-message conflict. Authorities: R-P1-004/014.
17. Reply to a saved or locked message; verify one flat chronology, collapsed M-summary plus M-last, explicit expansion, and no nested thread scroll. Authority: R-P1-016.
18. Resolve and reopen the whole thread; placement and message state remain independent. Authority: R-P1-007.
19. Switch File/Review surfaces and reload; the same canonical session, drafts, messages, origins, resolution, and output history converge. Authorities: R-P1-001/014.

### D. Share and output history

20. Open Share comments; New/All filter exact saved-message membership, draft-bearing messages are excluded, empty scope disables output, and Done/Escape closes without effect. Authority: R-P1-010.
21. Copy Markdown; inspect actual clipboard packet for deterministic path/source order, numbered excerpt, placement/side, one generated H1, unchanged authored Markdown, no generated absolute path, and no delivery claim. Authorities: R-P1-011/013.
22. Export JSON; inspect the actual file against the closed version-1 schema and confirm it represents the same batch/order. Authorities: R-P1-012/013.
23. After successful output, Share closes, threads remain open, messages lock and become handled; reopen History, inspect the exact attempt, Mark as not handled, and see exact saved bodies return to New without unlocking. Authority: R-P1-013.

### E. Real worktree refresh and continuity

24. Make a small same-source edit below every threshold; Review updates silently with no global bar and preserves comment/editor state. Authorities: R-RRC-002/003.
25. While the affected file owns semantic focus, create a threshold-reaching same-source change; current Review remains interactive, `Updating…` becomes `Update ready`, and Apply now installs atomically. Authorities: R-RRC-004-RRC-007.
26. Repeat promoted refresh, then leave the affected file/mode before readiness; candidate installs automatically and no `Update ready` remains. Authorities: R-RRC-004/005.
27. Create/edit/reply/share during promoted computation and hold; all commands remain usable and source validation stays fenced to the displayed Review until install. Authorities: R-RRC-005/007.
28. During a hold, produce a newer applicable candidate; only the newest complete candidate remains eligible, with no intermediate replay. Authority: R-RRC-008.
29. Move or delete the annotated source and install; immutable origin survives and current placement becomes exact, relocated, outdated, or unavailable rather than retaining a false coordinate. Authorities: R-P1-007; R-RRC-006/007.
30. Apply rapid file/Git/branch mutations; newest intent wins, obsolete completion cannot publish, loading settles, and last complete Review remains usable. Authorities: R-BLO-001/003-R-BLO-006/016.
31. Restart the isolated backend while Review is open; absence is explicit, fresh authority is obtained after recovery, and durable annotation/comparison state returns without cross-session data. Authorities: Dev R5-R6; R-BLO-007/012/016.

## Results

Chrome 151 connected through the configured extension. Automated gates previously green at `af7ffaf955` remain supporting evidence only.

- Workflow 1: `pass`. Chrome loaded the exact seeded linked worktree through Vite and the isolated Swift backend; no fixture data appeared.
- Workflow 2: `partial`. Launch-time `--seed-target HEAD` is durable explicit intent, so fresh no-intent default discovery is not reachable in this host. The on-demand picker correctly listed local and remote-tracking refs without preloading them into initial Review.
- Workflow 3: `pass`. After choosing Common comparison with `origin/main`, `Sources/TargetOnly.swift` was absent while feature-branch content was present.
- Workflow 4: `pass`. Chrome showed committed additions/deletions plus staged `docs/review.md`, staged+unstaged `Sources/StagedDraft.swift`, unstaged `Sources/ReviewEngine.swift`, and untracked `notes/untracked-review.md` with truthful status rows.
- Workflow 6: `pass` for ordinary catalog size. Opening Compare Worktree issued the on-demand experience, focused Search branches, showed distinct Local/Remote-tracking rows and exact OIDs, and displayed the required 30-day footer. Production-scale virtualization remains pending.
- Workflow 7: `pass` for remote-tracking selection. Selecting `origin/main` changed the durable target and Review projection; a pending loading status remained distinct until content settled.
- Workflow 12: `pass` for dragged-range confirmation and empty dismissal. Dragging additions lines 1-3 produced exactly one endpoint utility and no composer until click; the empty composer then disappeared on Escape with zero durable threads.
- Workflow 13: `fail` on reload recovery. First non-whitespace input became Save-enabled and persisted to canonical SQLite, but a full page reload rendered neither the draft nor thread. The reload annotation projection terminated failure; the UI then showed confirmed New/All zero without unavailable status. Investigation: `tmp/debug-workflows/2026-08-23-agent-studio-review-comments-review-draft-reload-projection/debug-investigation.md`.
- Workflows 25-28: `blocked` at current HEAD. The refresh controller/store exposes presentation, semantic-attention, and Apply-now APIs, but no production Review component consumes them; the coordination log records this UI-owned gap.
- Workflows 21-22: development-host proof will inspect exact `.md`/`.json` captures under the isolated data root. System clipboard and save-panel effects remain packaged-app proof by design.

Post-correction continuation:

- Workflow 5: `pass`. Full document reload bootstrapped the retained Review through the normal installation path and restored the living symbolic target.
- Workflow 8: `pass`. Common and Branch Tip were observably distinct. Basis selection alone left the current block unchanged; applying Branch Tip made target-only README/`TargetOnly.swift` changes visible as direct-tip reverse changes, while Common excluded them.
- Workflow 9: `pass`. Exact commit `4d9ad09ffad77343f43d331a2ecce916b81a666a` was basis-free and remained pinned while `origin/main` advanced to `51bba74a6ced7abf3df687eb0132348e4d76ae72`.
- Workflow 11/31: `pass` for controlled restart. With the backend absent, a fresh document stayed in Waiting rather than fabricating fixture/current success. Restart on the same port/data root automatically restored Review, `origin/main` intent, and the newest real-worktree bytes.
- Workflow 13: `fixed and pass`. Root cause was Swift synthesized encoding omitting required-nullable `activeEditToken` after draft edit-token release. A new focused test failed on the missing key and strict decode, the three-field custom encoder made it pass 1/1, and the rebuilt backend restored both draft and saved message on the exact Chrome reload reproduction.
- Workflow 14: `pass`. Explicit Save ended immediately with zero Saving controls and retained the exact saved body while the then-broken projection reported its separate unavailable state; after the encoder correction, projection converged normally.
- Workflow 17: `pass`. An output-locked root accepted a human reply. Save kept the two-message thread expanded with one root and one reply; collapse exposed `Expand 2 messages`.
- Workflow 18: `pass`. The saved thread resolved and reopened through explicit whole-thread commands without changing message content.
- Workflow 20: `pass`. New/All showed 1/1 for one eligible saved root and excluded the released-token draft. After output handling, New became 0 while All remained 1; unhandle restored New to 1 without unlocking.
- Workflow 21: `pass` for the development-host exact-byte effect. Chrome completed Copy, Share closed, and the 405-byte captured Markdown contained one H1, relative path, lines 1-3, numbered Swift excerpt, new side, exact placement, open resolution, and unchanged authored Markdown with no absolute path or delivery claim.
- Workflow 22: `pass` for development-host exact-byte export. Chrome completed Export and the captured file validated as schema `agentstudio.worktree-annotations.batch`, format version 1, one ordered entry, immutable origin/current placement, branch comparison origin, and raw authored body.
- Workflow 23: `pass` with keyboard disclosure. Reopened Share showed History (1), exact-byte Inspect matched the 405-byte capture, and Mark as not handled restored New (1). Pointer activation of the Collapsible History trigger had no effect in this run while Enter worked; pointer ownership remains to classify with the UI lane.
- Workflow 24/30: `pass` for a real small edit. Adding `ordinaryRefreshProof()` in the disposable worktree appeared in Chrome through Darwin observation and the existing pipeline; no global refresh bar appeared and the exact-commit target remained pinned.
- Workflow 19: `fail pending classification`. After Review → Files and selecting the same Swift file, canonical messages remained in the page store but only in the hidden Review subtree; File rendered zero visible annotation rows. A read-only ownership trace is active.
- Workflow 29 deletion backend boundary: `pass` in permanent deterministic integration at `c58820519`. The corrected test seeds the dirty tracked file before startup, waits for initial Git status settlement, deletes it as the only post-start filesystem mutation, requires an exact deletion `FileChangeset`, then requires a newer Review containing `basePath == "tracked.txt"` and `headPath == nil`. This rules out a general seeded-observer deletion defect. The earlier long-running Chrome fixture miss remains a sequence-specific observation and must be rerun after the File/Review UI owner lands; no observer rewrite is justified by current evidence.
- Workflows 21-23 permanent composed proof: `pass` for both File and Review surfaces. The real Chrome/Vite/comm-worker/Swift journey now requires exactly one newly written Markdown capture, validates the authored body, one generated H1, and no absolute worktree path; then unhides membership, drives Export JSON, requires exactly one newly written JSON capture with schema `agentstudio.worktree-annotations.batch`, format version 1, batch ordinal 0, one entry, and the exact authored body; finally it proves two durable History attempts and restores New membership before reload. Exact commands each passed 1/1 with 6 skipped.
- Workflows 14/16/21-23 combined multi-message proof: `pass`, 2/2 with 5 skipped. File and Review use distinct bodies against one shared fixture. The second JSON capture truthfully contains both canonical messages with contiguous batch ordinals and unique message IDs; each per-surface capture includes the current authored body. This supersedes the preceding one-entry-only wording, which described the isolated per-surface runs.
- Workflows 19/31 process-restart persistence floor: `pass`, permanent real E2E 1/1 with 7 skipped. Chrome authored distinct File and Review messages, process A stopped cleanly, process B started with a different PID over the same isolated data root, and a fresh Chrome document recovered the File message in File and Review message in Review. Review-origin visibility in File remains separately pending the thin File Pierre owner.
- Workflow 19 Review-origin → File convergence: permanent `RED`. The restart journey navigates File directly to the exact Review-origin path and waits for ready content; the recovered Review body never renders. This cleanly separates native placement/SQLite recovery (green) from the File Pierre eligibility predicate (missing).
- Workflows 25-26 promoted hold/Apply/automatic release: permanent `RED` with a real ten-commit worktree mutation. While the affected Review file remains selected, the displayed package changes immediately (`installedWithoutHold`) instead of retaining A and presenting `Update ready`. This proves production semantic attention is not wired; the same test already carries the subsequent Apply-now and unaffected-file automatic-install assertions for the UI owner to turn green.
- Workflows 25-26 promoted hold/Apply/automatic release: `fixed and pass`, permanent real E2E 1/1 with 8 skipped. Chrome selected the affected file, a private-index fixture advanced the observed ref by exactly ten commits without changing worktree bytes, and the production pipeline retained the old target behind `Update ready`. Enter on Apply now installed the exact target OID and the real `review.publication.applied` call completed before the next mutation. A same-OID ordinary catch-up could not satisfy the target-correlated harness. The second exact ten-commit advance held again; selecting an unaffected file released it automatically. Each installed generation has a held lifecycle sample with class `promoted` and reason `commits`. Focused supporting proof: installed Chrome 28/28, TypeScript unit/harness 16/16, Swift refresh/carriage/composition 38/38, and BridgeWeb typecheck pass.
