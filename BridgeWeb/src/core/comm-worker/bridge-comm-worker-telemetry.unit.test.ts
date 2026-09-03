import { describe, expect, test } from 'vitest';

import { recordBridgeCommWorkerTaskTelemetry } from './bridge-comm-worker-telemetry.js';

describe('Bridge comm worker telemetry', () => {
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
