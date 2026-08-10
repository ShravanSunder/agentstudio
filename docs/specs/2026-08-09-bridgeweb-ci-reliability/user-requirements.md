# BridgeWeb CI Reliability — User Requirements

## Goal boundary

Make Bridge File Viewer browser validation deterministic and correct the same-file refresh behavior that currently destroys scroll position.

```text
Developer changes File Viewer
          │
          ▼
CI waits for the exact work caused by the test action
          │
          ├─ failure means a real unfinished or incorrect transition
          └─ success means no related work escapes the test boundary

User refreshes the same file
          │
          ▼
new contents replace old contents without destroying the viewport
```

## Authorized needs

| ID | Affected class | Need and outcome | Priority | Authority |
| --- | --- | --- | --- | --- |
| U1 | Agent Studio developers | File Viewer browser tests report real failures instead of depending on animation-frame timing. | Required | User-authorized in this design request |
| U2 | Agent Studio users | Refreshing the same logical file preserves its viewport while replacing its contents. | Required | User-authorized in this design request |
| U3 | Agent Studio developers | Failed timing workarounds are removed only after their underlying lifecycle or identity boundary replaces them. | Required | User-authorized in this design request |
| U4 | Maintainers | The fix stays local to File Viewer query completion, same-file replacement, and their browser proof. | Required | User-authorized in this design request |

## Constraints and non-goals

- Keep the strict React error guard.
- Do not add sleeps, fixed-frame waits, retries, timeout inflation, or warning suppression.
- Do not introduce a generic async framework, global scheduler, persistence, telemetry system, or broad Bridge runtime redesign.
- Do not change different-file navigation: it still resets content and scroll position.
- Do not promise that old same-file content disappears while replacement content is loading; retaining it briefly is acceptable.
- Classify existing bounded condition polling before removal. Polls that observe a real DOM condition are not automatically cruft.

## Acceptable evidence

- Deterministic automated proof that one query action settles its exact accepted outcome before assertions or teardown.
- Real browser proof that same-file replacement never publishes an intervening empty CodeView, preserves the connected scroll owner, and preserves its final viewport.
- Companion proof that different-file navigation and intentional user scroll-to-top still end at zero.
- The complete BridgeWeb validation lane remains green without weakening its failure guard.
