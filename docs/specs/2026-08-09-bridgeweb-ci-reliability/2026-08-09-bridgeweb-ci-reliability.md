# BridgeWeb CI Reliability — Specification

Requirements: [user-requirements.md](user-requirements.md)

## Observable outcome

```text
Test interaction                      Same-file refresh
      │                                      │
      ▼                                      ▼
exact query outcome settles           old generation stays mounted
      │                                      │
      ▼                                      ▼
React publication commits             new generation replaces it
      │                                      │
      ▼                                      ▼
assertion / teardown begins            viewport remains stable
```

## Requirements

### R1 — Causally complete query tests

For each File Viewer query-changing interaction, browser validation MUST wait for the outcome caused by that exact interaction before asserting or tearing down.

- A changed query completes only after its accepted display transaction has published to React.
- An unchanged query completes with an explicit unchanged outcome.
- Completion MUST NOT be inferred from elapsed frames, an idle-looking queue, or unrelated worker counters.
- Superseded query work MUST NOT satisfy the completion obligation for a newer interaction.

Basis: U1, U3, U4.

### R2 — Strict React failure reporting

Unexpected React `act(...)` warnings, console errors, window errors, and unhandled rejections MUST continue to fail browser validation. The solution MUST prevent escaped updates rather than suppressing their evidence.

Basis: U1, U3.

### R3 — Same-file generation replacement

When `(fileId, displayPath)` is unchanged and only the content generation changes, the File Viewer MUST replace the old generation with the new generation without presenting an intervening empty CodeView.

- The connected scroll owner and its viewport MUST survive successful replacement.
- Old content MAY remain visible beneath loading presentation until the replacement is ready.
- A failed, cancelled, or superseded replacement MUST NOT install stale new content.

Basis: U2, U3, U4.

### R4 — Navigation and user intent remain distinct

When `(fileId, displayPath)` changes, the File Viewer MUST reset the old content and begin the new file at the top. An intentional user scroll to the top MUST remain at zero; a numeric zero callback alone MUST NOT be classified as a refresh reset.

Basis: U2, U4.

### R5 — Proportional cleanup

Fixed-frame query settlement and same-file temporal scroll-recovery logic MUST be removed once the causal completion and stable-identity paths own those behaviors. Bounded waits for named observable conditions MAY remain when they cannot falsely establish global quiescence.

Basis: U3, U4.

## Failure contract

```text
query changed ──► accepted transaction ──► React publication ──► complete
      │                    │
      ├─ superseded ───────┴──────────────────────────────► not complete
      └─ unchanged ───────────────────────────────────────► complete unchanged

same file A@1 ──► replacement fails/cancels
      └────────────────► keep A@1 or show existing error/loading contract;
                         never publish A@2 as accepted
```

## Proof obligations

| ID | Observable evidence |
| --- | --- |
| V1 | A browser query interaction cannot complete its wait before the exact unchanged or accepted-transaction outcome and resulting React publication. |
| V2 | The strict browser failure guard remains enabled and the query lifecycle browser coverage emits no `act(...)` warning. |
| V3 | Real CodeView calls transition `A@1 → A@2`, never `A@1 → [] → A@2`; the same connected owner retains its settled scroll position. |
| V4 | Different-file navigation resets to zero, intentional user scroll-to-top remains zero, and superseded generations cannot publish. |
| V5 | Focused browser coverage and the complete BridgeWeb validation lane pass without wall-clock accommodation. |
