import { describe, expect, test } from 'vitest';

import { readBridgeCommWorkerAbsoluteNowMilliseconds } from './bridge-comm-worker-clock.js';

describe('Bridge comm worker absolute clock', () => {
	test('normalizes main and worker clocks with different time origins', () => {
		const mainIssuedAtMilliseconds = readBridgeCommWorkerAbsoluteNowMilliseconds({
			timeOrigin: 1_000,
			now: () => 20,
		});
		const workerHandlerStartMilliseconds = readBridgeCommWorkerAbsoluteNowMilliseconds({
			timeOrigin: 900,
			now: () => 150,
		});

		expect(workerHandlerStartMilliseconds - mainIssuedAtMilliseconds).toBe(30);
	});
});
