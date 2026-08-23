import { describe, expect, test } from 'vitest';

import {
	readBridgeCommWorkerAbsoluteNowMilliseconds,
	recordBridgeCommWorkerTaskTelemetry,
} from './bridge-comm-worker-telemetry.js';

describe('Bridge comm worker telemetry clock', () => {
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

	test('records only the bounded semantic class for message admission', () => {
		const samples: Parameters<
			NonNullable<
				Parameters<typeof recordBridgeCommWorkerTaskTelemetry>[0]['telemetryClient']
			>['record']
		>[0][] = [];
		recordBridgeCommWorkerTaskTelemetry({
			command: 'annotationCommand',
			durationMilliseconds: 1,
			lane: 'selected',
			semanticClass: 'urgent_action',
			taskKind: 'message_handler',
			telemetryClient: {
				record: (sample): void => {
					samples.push(sample);
				},
			},
		});

		expect(samples).toHaveLength(1);
		expect(samples[0]?.stringAttributes).toMatchObject({
			'agentstudio.bridge.worker.command': 'annotationCommand',
			'agentstudio.bridge.worker.semantic_class': 'urgent_action',
		});
		expect(JSON.stringify(samples[0])).not.toContain('exact durable body');
	});
});
