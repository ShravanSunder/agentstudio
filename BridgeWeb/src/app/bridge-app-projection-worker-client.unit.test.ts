import { readFile } from 'node:fs/promises';

import { describe, expect, test } from 'vitest';

const sourceUrl = new URL('./bridge-app.tsx', import.meta.url);

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
			/const flushTelemetry = useCallback\(\(flushProps: BridgeTelemetryFlushProps = \{\}\): void => \{\s+telemetryRecorderRef\.current\.flush\(flushProps\);\s+\}, \[telemetryRecorderRef\]\);/u.test(
				source,
			),
		).toBe(true);
	});
});
