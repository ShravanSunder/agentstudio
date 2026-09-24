// The one declaration of every BridgeWeb Vitest suite's hang bound. A hang bound
// only stops a wedged run; tests wait on application events or DOM conditions,
// never on time, so these values are never tuned to make a test pass. The unit
// and node-integration bounds are 120 s (owner decision 2026-09-24); every other
// value equals the bound the suite already ran under.

// A hang bound only fires on a real hang; it is set once per suite and never
// raised for a failing test. Waits inside tests are judged by events
// (no-timed-wait-in-tests).
export const unitTestTimeoutMilliseconds = 120_000;

export const nodeIntegrationTestTimeoutMilliseconds = 120_000;

export const browserIntegrationTestTimeoutMilliseconds = 60_000;

export const browserBenchmarkTestTimeoutMilliseconds = 15_000;

export const scriptBenchmarkTestTimeoutMilliseconds = 5_000;

// A real-backend journey on a 3-vCPU runner may legitimately be slow, so the
// E2E bound is wide; it still only stops a wedged run from hanging forever.
export const endToEndTestTimeoutMilliseconds = 600_000;

export const endToEndHookTimeoutMilliseconds = 60_000;
