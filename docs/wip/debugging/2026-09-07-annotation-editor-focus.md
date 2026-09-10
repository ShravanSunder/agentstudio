# Annotation editor focus boundaries

## 2026-09-07 — editor padding versus thread background

Editing lifetime, browser focus, thread expansion, and selected source range are
separate state. Blur alone must not end editing or discard the draft.

| Input | Editing | Focus | Thread |
| --- | --- | --- | --- |
| Edit action | Open existing message editor | Textarea | Active/expanded |
| Textarea click | Same editor and draft | Native caret position | Remains active |
| Editor padding click | Same editor and draft | Same textarea, retained caret | No focus takeover |
| Save/Revert focus | Same editor until action completes | Action button | Remains active |
| Thread background click | Editor stays open | Thread | Active; editor ring absent |
| Outside-thread click | Editor stays open | Clicked external target | No editor focus takeover |
| Escape inside focused thread with editor | Existing registered flush/exit | Existing restoration target | Does not implicitly discard draft |
| Nested menu Escape | Editor unchanged | Nested control owns dismissal | Thread handler yields |

Observed failure: thread capture handler classified only links/buttons/inputs as
interactive. Editor padding was classified as thread background and explicitly
focused the thread. Regression failed with SECTION active instead of TEXTAREA.

Correction: thread handler recognizes an editing surface as interaction-owned;
the editor surface focuses its textarea for blank-padding clicks only. It does
not intercept textarea caret placement or action-button clicks. Existing state
owners and draft lifecycle remain unchanged.

Proof: inline-shell browser regression covers blur, padding click, same textarea
identity, unchanged contents, retained selection offset, ring state and Escape.
This does not yet prove every reported native flicker path; no native success
claim follows from the browser harness alone.
