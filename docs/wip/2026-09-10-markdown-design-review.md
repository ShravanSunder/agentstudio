# Markdown production design review

Independent invocation/result: `2026-09-10-markdown-design-review`, Astra medium,
fresh context, read-only, three-artifact mode. Covered base `feb5e6cfd` and the
three documents under `docs/specs/2026-09-10-rendered-markdown-annotations/`.

The reviewer returned complete, needs-revision with two Program Design findings:

1. Article identity replacement removed disposable hosts without a defined active
   editor handoff. Evidence: composer local body/cursor/admission state and
   `prepareForInstallation` in worktree-annotation-composer.ts:220; shared registry
   preparation in worktree-annotation-surface-provider.ts:328. U4/U5, R5/R6 at risk.
2. Successor failure discarded the retained article through
   use-bridge-markdown-presentation.ts:128 and canvas failure state. U5/R6 at risk.

Parent disposition: both accepted after opening the named sources. One bounded
Program Design correction defines an installation gate: prepare, retain actual
article/editor hosts while editing, recheck current identity after await, install
only after edit exit and compatible projection; retain old ready content on
same-file failure with Retry. Initial load failure remains unchanged.

Parent verification: the corrected ownership/flow section explicitly covers new
composers, replies, message edits, failed/delayed preparation, continued typing,
obsolete candidate completion, delayed receipts/projection, retry and file switch.
Retaining mounted hosts avoids the proposed remount/handoff complexity entirely.
Requirements and Specification meaning did not change. All U1-U7 and R1-R8 remain
covered. No supported residual requires a second independent round.

Result: design-ready for planning, with original independent findings plus these
parent-verified correction anchors. No production implementation, tests, native
proof, implementation review or PR-readiness claim is made by this review.
