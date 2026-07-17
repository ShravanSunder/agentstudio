import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

const sourceUrl = new URL('./bridge-app-review-viewer-mode.tsx', import.meta.url);

describe('BridgeApp projection-worker hard cut', () => {
	test('does not restore a Review projection-worker client', async () => {
		const source = await readFile(sourceUrl, 'utf8');

		expect(source).not.toContain('projectionWorkerClient');
		expect(source).not.toContain('createBridgeReviewProjectionWebWorkerClient');
		expect(source).not.toContain('defaultProjectionWorkerClient');
	});

	test('does not retain the deleted projection-worker telemetry flush seam', async () => {
		const source = await readFile(sourceUrl, 'utf8');

		expect(source).not.toContain('BridgeTelemetryFlushProps');
		expect(source).not.toContain('flushTelemetry');
	});
});
