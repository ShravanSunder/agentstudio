# Contracts / Tests Lane

Agent: `019ef29e-b17b-7483-a1b5-02ff9400d474`

Verdict: important finding accepted and fixed.

Finding:

- Review-viewer allowlist narrowing was not protected by a permanent negative
  test. The Swift registry now excludes `worktree-file/file-content` from the
  review viewer, but the regression suite did not directly assert that
  review-viewer parsing rejects that route.

Disposition:

- Accepted.
- Added `BridgeSchemeHandlerTests.test_reviewViewerResourceAllowlistRejectsWorktreeFileContent`.

Proof:

- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-fast -- --filter 'BridgeContentStoreTests|BridgeSchemeHandlerTests'`
  - exit 0
  - 70 tests in 2 suites passed for selected non-WebKit suites.
- `SWIFT_TEST_TIMEOUT_SECONDS=60 SWIFT_TEST_PREBUILD_TIMEOUT_SECONDS=180 mise run test-webkit`
  - exit 0
  - WebKit serialized lane passed in 90.70s.
