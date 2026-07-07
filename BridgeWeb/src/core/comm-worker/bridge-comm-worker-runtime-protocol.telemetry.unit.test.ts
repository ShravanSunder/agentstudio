import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import { encodeBridgeWorkerSelectCommand } from './bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from './bridge-comm-worker-runtime-protocol.js';
import {
	createRecordingBridgeCommWorkerPort,
	makeWorkerReviewContentMetadata,
} from './bridge-comm-worker-runtime-protocol.test-support.js';

describe('Bridge comm worker runtime protocol telemetry', () => {
	test('records command queue wait and handler duration from typed dispatch timestamp', () => {
		const clockReadings = [18, 18, 22];
		const telemetrySamples: BridgeTelemetrySample[] = [];
		const { dispatch } = createRecordingBridgeCommWorkerPort();

		registerBridgeCommWorkerRuntimePortProtocol(dispatch.port, {
			bridgeDemandRank: { lane: 'selected', priority: 0 },
			budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 50 },
			contentItems: [makeWorkerReviewContentMetadata({ itemId: 'item-1' })],
			contentRequestDescriptors: [],
			now: () => {
				const value = clockReadings.shift();
				if (value === undefined) {
					throw new Error('Unexpected runtime clock read.');
				}
				return value;
			},
			renderSemantics: [],
			rows: [{ id: 'item-1', parentId: null, index: 0 }],
			schedulePreparationDrain: (): void => {},
			telemetryClient: {
				record: (sample): void => {
					telemetrySamples.push(sample);
				},
			},
		});

		dispatch.message(
			encodeBridgeWorkerSelectCommand({
				epoch: 3,
				issuedAtMilliseconds: 10,
				requestId: 'request-select',
				selectedItemId: 'item-1',
				selectedSource: 'user',
			}),
		);
		expect(telemetrySamples).toContainEqual(
			expect.objectContaining({
				name: 'performance.bridge.worker.task',
				durationMilliseconds: 4,
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.result': 'success',
					'agentstudio.bridge.worker.command': 'select',
					'agentstudio.bridge.worker.lane': 'selected',
					'agentstudio.bridge.worker.task_kind': 'message_handler',
				}),
				numericAttributes: expect.objectContaining({
					'agentstudio.bridge.worker.handler_duration_ms': 4,
					'agentstudio.bridge.worker.queue_wait_ms': 8,
				}),
			}),
		);
	});
});
