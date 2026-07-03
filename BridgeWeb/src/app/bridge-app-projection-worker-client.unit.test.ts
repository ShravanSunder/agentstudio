import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

// The projection worker client and telemetry flush are review-only concerns, so they live in
// the review viewer mode, not the app root. (Historically they were inlined in bridge-app.tsx;
// they moved when BridgeReviewViewerMode was extracted, so these ownership guards read that
// owner. The patterns below tolerate formatter line reflow but assert the same contracts.)
const sourceUrl = new URL('./bridge-app-review-viewer-mode.tsx', import.meta.url);

describe('BridgeApp projection worker client ownership', () => {
	test('does not create the native default projection worker when a client is provided', async () => {
		const source = await readFile(sourceUrl, 'utf8');

		expect(source).not.toContain('const defaultProjectionWorkerClient = useMemo(');
		expect(
			/props\.projectionWorkerClient === undefined\s+\? createBridgeReviewProjectionWebWorkerClient\(\)\s+: props\.projectionWorkerClient/u.test(
				source,
			),
		).toBe(true);
	});

	test('forwards forced projection telemetry flushes to the recorder', async () => {
		const source = await readFile(sourceUrl, 'utf8');

		expect(
			/const flushTelemetry = useCallback\(\s*\(flushProps: BridgeTelemetryFlushProps = \{\}\): void => \{\s+telemetryRecorderRef\.current\.flush\(flushProps\);\s+\},?\s*\[telemetryRecorderRef\],?\s*\);/u.test(
				source,
			),
		).toBe(true);
	});
});
