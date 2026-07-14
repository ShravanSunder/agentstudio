import { describe, expect, test, vi } from 'vitest';

import { createInertBridgeCommWorkerClient } from './bridge-comm-worker-client.js';

describe('Bridge comm worker client', () => {
	test('does not issue Swift fetch telemetry or demand side effects from the inert shell', async () => {
		const postMessage = vi.fn();
		const swiftFetch = vi.fn();
		const telemetryFlush = vi.fn();
		const demandSideEffect = vi.fn();
		const client = createInertBridgeCommWorkerClient({
			postMessage,
			onSwiftFetch: swiftFetch,
			onTelemetryFlush: telemetryFlush,
			onDemandSideEffect: demandSideEffect,
			createRequestId: (): string => 'request-select',
		});

		const health = await client.select({
			epoch: 1,
			selectedItemId: 'item-1',
			selectedSource: 'user',
			surface: 'fileView',
		});

		expect(postMessage).toHaveBeenCalledOnce();
		expect(postMessage.mock.calls[0]?.[0]).toMatchObject({
			command: 'select',
			direction: 'mainToServerWorker',
			kind: 'command',
			requestId: 'request-select',
			transferDescriptors: [],
		});
		expect(health).toEqual({
			wireVersion: 1,
			direction: 'serverWorkerToMain',
			transferDescriptors: [],
			kind: 'health',
			requestId: 'request-select',
			status: 'ready',
		});
		expect(swiftFetch).not.toHaveBeenCalled();
		expect(telemetryFlush).not.toHaveBeenCalled();
		expect(demandSideEffect).not.toHaveBeenCalled();
	});
});
