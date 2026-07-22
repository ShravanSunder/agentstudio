# Accepted-C Visual Onlook

Date: 2026-06-26
Scope: BridgeViewer shared-app Gate 0.a accepted-C visual contract.

Inputs:

- `tmp/bridge-viewer-design-proof/2026-06-26T05-41-43-291Z-accepted-c-refresh/files.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T05-41-43-291Z-accepted-c-refresh/review-diff.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T05-41-43-291Z-accepted-c-refresh/review-file-target.png`
- `tmp/bridge-viewer-design-proof/2026-06-26T05-41-43-291Z-accepted-c-refresh/accepted-c-design-proof.json`

Rubric:

- content topbar belongs only over the left content canvas;
- right rail starts at `y=0` and remains full height;
- `Files | Review` switcher is inside the content topbar;
- FileViewer and ReviewViewer share compact control scale;
- no standalone `WorktreeFileApp` or minimal/raw file viewer surface is visible.

Result:

- Topbar placement: PASS. The artifact records `topbarRect` from `0..1708`,
  while the rail starts at `x=1708`.
- Rail top alignment: PASS. The artifact records `railRect.top = 0` and
  `railRect.bottom = 1342`.
- Switcher placement: PASS. The artifact records `switcherInsideTopbar = true`
  for Files, Review diff, and Review file-target routes.
- Shared compact controls: PASS. The artifact records one shared search
  control and one rail toolbar at `28px` height on all three routes.
- Second-app guard: PASS. The artifact records
  `standaloneWorktreeFileAppCount = 0` on all three routes.
- Visible loading/unavailable guard: PASS. The artifact records
  `loadingTextVisible = false` and `contentUnavailableVisible = false`.

Open note:

- This onlook validates accepted-C geometry and shared-shell visual contract.
  It does not close FileViewer click-to-ready latency, speculative preload,
  Review route fanout/content pressure, implementation review, or native
  Agent Studio Bridge/WKWebView proof.
