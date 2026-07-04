import { describe, expect, expectTypeOf, test } from 'vitest';

import {
	BRIDGE_WORKER_WIRE_VERSION,
	bridgeWorkerMainToServerMessageSchema,
	bridgeWorkerServerToMainMessageSchema,
	parseBridgeWorkerMainToServerMessage,
	type BridgeWorkerMainToServerMessage,
} from './bridge-worker-contracts.js';

describe('BridgeWorkerContracts', () => {
	test('rejects untyped main to server worker messages at schema boundary', () => {
		const selectCommand = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			command: 'select',
			requestId: 'request-select',
			epoch: 3,
			selectedItemId: 'item-1',
			selectedSource: 'user',
		} satisfies BridgeWorkerMainToServerMessage;

		expect(parseBridgeWorkerMainToServerMessage(selectCommand)).toEqual(selectCommand);
		expect(bridgeWorkerMainToServerMessageSchema.safeParse(selectCommand).success).toBe(true);
		expect(
			bridgeWorkerMainToServerMessageSchema.safeParse({
				...selectCommand,
				wireVersion: BRIDGE_WORKER_WIRE_VERSION + 1,
			}).success,
		).toBe(false);
		expect(
			bridgeWorkerMainToServerMessageSchema.safeParse({
				wireVersion: BRIDGE_WORKER_WIRE_VERSION,
				direction: 'mainToServerWorker',
				kind: 'command',
				command: 'startFetch',
				requestId: 'request-fetch',
			}).success,
		).toBe(false);

		const healthEvent = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'serverWorkerToMain',
			kind: 'health',
			requestId: 'request-select',
			status: 'ready',
		};
		expect(bridgeWorkerServerToMainMessageSchema.safeParse(healthEvent).success).toBe(true);

		const invalidCommand: BridgeWorkerMainToServerMessage = {
			wireVersion: BRIDGE_WORKER_WIRE_VERSION,
			direction: 'mainToServerWorker',
			kind: 'command',
			// @ts-expect-error Unknown command shapes must be rejected before runtime.
			command: 'startFetch',
			requestId: 'request-fetch',
		};
		expectTypeOf(invalidCommand).toMatchTypeOf<BridgeWorkerMainToServerMessage>();
	});
});
