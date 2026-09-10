# PR2 — upstream stable zmx update

Scope: AgentStudio pin/build changes only; no retained vendor source patches or
vendor repository commits. PR3 IPC activity/indicators excluded.

- [x] Start feat/zmx-update from origin/main c64e3cad.
- [x] Verify upstream stable v0.8.1 tag -> 8bab1f0173b07e79835ea372d749af3dbf0d0842.
- [x] Upstream source retains OSC133 redraw rewrite and internal resize suppression.
- [x] Downloaded macOS arm64 release checksum matches upstream:
  1d86b1c9fba47fa707a6f0e976b20510b07c1c26d0ed010b9414b2a2c5e6beef.
- [x] Isolated old bundled daemon / new release client: list, history, real PTY
  attach output and resize37x111 passed. Test sessions and roots cleaned.
  This proves those upgrade paths only, not rollback or all shell rendering.
- [x] Commit11ed537fc changes upstream gitlink/url, task-scoped Zig0.16 and shared
  mise task use in CI/release/benchmarks. Ghostty stays on Zig0.15.2.
- [ ] Complete mise run setup --use-local-vendors (session16893).
  Initial setup stopped on committed-gitlink guard; committed update then resumed.
  Existing Ghostty helper transient patch restored; bothvendor source trees clean.
- [ ] Focused zmx identity/backend/integration/vendor-wiring tests.
- [ ] Durable mixed-version regression coverage and exact new-daemon lifecycle proof.
- [ ] Required aggregate and independent review, then PR.

Evidence logs: tmp/zmx-pr2/setup-committed.log/.exit, focused.log/.exit.
No production/debug session or data changes. No compatibility claim for old-client
against new-daemon rollback; that needs separate proof if supported.

## Authorized Ghostty trial

User selected82232ecde55405559dec29c5466cb9e39938cb41 (1.3.2-dev/Zig0.16),
with no vendor source modifications. Removed temporaryvendorpatch from localbuild.
Setup3exit0; both vendor trees clean. CopiedXCFramework required lib-prefixedarchive;
AgentStudio-owned normalizer updates copiedarchive/plist and stripsdebuginfo.
CI/release/benchmarks use sharedcopytask. Clipboardadapter uses newtypedpayloads,
explicitbyte lengths, plain-textrequests only; unsupportedlisting/MIME rejected.
Focusedcallback+vendorwiring14tests/2suitespass; appcompiled/linked.
DebugLaunchServiceslaunch PID58977, vx09identity. Screenshot tmp/zmx-pr2/ghostty-trial.png
showsrestoredshellprompts; exactPIDstartupqueryfoundnosurfaceinitializationerrors.
This is startup/renderingproofonly. Clipboardroundtrip/interaction, fullaggregate,
independentreview, durablepackagingtests and finalPR remain outstanding.
Productionnotrestartedormodified. No vendor sourcepatchesretained.

## Beta delivery decision — 2026-09-10

Owner explicitly requests beta publication from feat/zmx-update, NO merge and no
stable replacement. Owner explicitly retains existing clipboard automatic approval
for this beta after discussion of terminal-program reads/writes and unsafe paste.
No persistent Kitty grant is added (remember=false). Consent UI is deferred.

Review fixes: map standard and app selection pasteboards separately, reject primary;
select one text/plain write by explicit length, reject ambiguous/unsupported payloads;
preserve missing-vs-empty read distinction; validate normalizer paths/symlinks.
Focused review-fix tests18/2pass. Packaging bounds have three fixture cases.
General clipboard paste was observed in a new debug tab; UI changed during follow-up,
so complete command-output/copy roundtrip is not claimed. No further UI control.
Full aggregate and final review pending, followed by PR/CI and beta tag only.
