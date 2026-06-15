import { describe, expect, test } from 'vitest';

import type { BridgeRPCCommand } from './bridge-rpc-client.js';
import { createBridgeTelemetryEventSink } from './bridge-telemetry-event-sink.js';

describe('bridge telemetry event sink', () => {
	test('flushes batches through the exact system bridge telemetry method', () => {
		const commands: BridgeRPCCommand[] = [];
		const sink = createBridgeTelemetryEventSink({
			methodName: 'system.bridgeTelemetry',
			rpcClient: {
				sendCommand: (command: BridgeRPCCommand): boolean => {
					commands.push(command);
					return true;
				},
			},
		});

		const didFlush = sink.flush({
			schemaVersion: 1,
			scenario: 'bridge-runtime',
			samples: [],
		});

		expect(didFlush).toBe(true);
		expect(commands).toEqual([
			{
				method: 'system.bridgeTelemetry',
				params: {
					schemaVersion: 1,
					scenario: 'bridge-runtime',
					samples: [],
				},
			},
		]);
	});
});
