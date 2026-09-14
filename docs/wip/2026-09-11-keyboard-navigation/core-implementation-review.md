# Keyboard core implementation review and correction

Reviewed `8af534f670eb0f7396b7921b2de1ac0e03f71c15`, source/test head `10383d28f`, against the unchanged sidebar core, terminal v2 and visible-spatial ready plans. Bounded diff: `0444368a2..2c58e3484` plus `990c947db..8af534f67`; current source includes merged main `b52a75a92`.

Spec-compliance, four independent whole-file chunks, proof challenge and dispel completed. UI, navigation metadata/transport and terminal/spatial/catalog chunks found no implementation defects. Parent verified candidate anchors and source; every delivered subsystem mapped to a confirmed obligation. Review history restored from original session: one prior implementation-remediation pass (terminal nil-source guard); one recovery used, never reset.

## Accepted corrections

- **PINNED-CAPTURE-1 — important, implementation owner.** Core plan says “All list-sized derivation is off MainActor.” Pinned request capture calls `RepositoryTopologyAtom.captureReadSnapshot`; main's new absence getters rebuild `Set(dictionary.keys)` on every call. Base stored the set. Parent confirms this is a main-integration regression, not a new product/design boundary. Smallest correction retains canonical absence records in the existing read snapshot and preserves keyed availability/association/path checks. No new atom, cache, store, event, coordinator or public semantic contract. Removing only set reconstruction satisfies the deletion test; deleting availability checks would weaken behavior.
- **WIP-STATUS-1 — minor, documentation owner.** The current review map and terminal discussion still opened with pre-implementation/failed-aggregate status. Reconcile those entry lines to actual implementation/review/proof, preserving historical failures and pending preview/timing.

Confirmation for capture: structural regression for no MainActor absence-set projection; permanent snapshot availability/ownership/isolation scenarios; focused topology/pinned regression, lint and fresh aggregate after code correction; marker-scoped capture/worker observation on corrected native app. No wall-clock unit threshold.

## Proof disposition

`MISE_RAW=1 mise run test` passed on `10383d28f`; reviewed HEAD changes docs only. Independent proof lane ran `mise run lint` and two `git diff --check` checks, all exit0, without product/test edits. It did not rerun aggregate under its narrower no-install grant; original operator log and source freeze establish the historical aggregate result.

The proof supplement inspected original ordered CUA inputs, AX results and PNGs: terminal68-row viewport moved61/22 rows; sidebar P/R/F, filter return, groups, offscreen9, Bridge/custom and drawer reveal,250/436pt overlays and corrected focus were corroborated; mixed hidden-sidebar pinned cycle was corroborated. Exact marker query stayed8 before/after40 selection keys. These are historical native observations with current-source regression support, not a fresh post-correction run.

Fresh pinned phase/timing remains unavailable. Exact query exited0 with0 matching records; PID86213 GUI capture reports locked session. Schema tests cannot substitute for live measurement. Preview remains owner-pending; detached-drawer invariant and nested WebKit DOM focus remain deferred.

## Result and next owner

Review result `blocked-input` for fresh live timing, with the two accepted corrections above routed to existing owners for independent progress. Current source coverage is invalidated when the capture correction lands; affected fresh proof and review are required. The next bounded correction is remediation pass2, not a new recovery or a design round. No PR-ready or whole-goal completion claim.

Detailed temporary receipts: `tmp/sidebar-keyboard-design/core-review-packet.md`; `/tmp/keyboard-{ui,worker,pinned,terminal}-review.md`; `/tmp/keyboard-proof-review.md`; `/tmp/keyboard-proof-native-evidence-supplement.md`; `/tmp/keyboard-core-dispel.md`. Original native and review evidence is retained in the current session, with ordinal pointers in the proof supplement.

## Remediation pass 2: scoped proof

The same-owner capture correction and WIP status corrections are applied. Expected RED:5 architecture tests,4 passed/1 failed with2 issues from derived absence getters; initial sandbox failure ran0 tests and is not RED. GREEN:19 tests/5 suites,0 issues; format, lint (SwiftLint0/2664 files, architecture and release checks) and diff-check all exit0. Source changes are one topology snapshot file and two permanent test files. Captured availability/absence, wrong-owner/missing identities, path exclusion and old-snapshot isolation pass for both repository/worktree absence. Fresh aggregate and corrected-source review remain; live timing still needs unlocked GUI. Logs use `tmp/sidebar-keyboard-design/pinned-capture-{red-authorized,green-*}`.
