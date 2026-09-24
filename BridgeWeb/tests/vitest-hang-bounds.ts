// The one declaration of every BridgeWeb Vitest suite's hang bound. A hang bound
// only stops a wedged run; tests wait on application events or DOM conditions,
// never on time, so these values are never tuned to make a test pass. Each value
// equals the bound the suite already ran under (Vitest's 5 s node and 15 s
// browser defaults where a config declared none).

export const unitTestTimeoutMilliseconds = 5_000;

export const nodeIntegrationTestTimeoutMilliseconds = 5_000;

export const browserIntegrationTestTimeoutMilliseconds = 60_000;

export const browserBenchmarkTestTimeoutMilliseconds = 15_000;

export const scriptBenchmarkTestTimeoutMilliseconds = 5_000;

// A real-backend journey on a 3-vCPU runner may legitimately be slow, so the
// E2E bound is wide; it still only stops a wedged run from hanging forever.
export const endToEndTestTimeoutMilliseconds = 600_000;

export const endToEndHookTimeoutMilliseconds = 60_000;
