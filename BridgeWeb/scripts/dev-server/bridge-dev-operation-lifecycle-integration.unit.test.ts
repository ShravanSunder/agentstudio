import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import { createBridgeDevTelemetrySink } from './bridge-dev-telemetry.js';

describe('Bridge dev operation lifecycle integration', () => {
	test('status exposes bounded paired lifecycle reduction', async () => {
		let timestamp = 1_782_218_790_000_000_000n;
		const sink = createBridgeDevTelemetrySink({
			fetchImpl: async (): Promise<Response> => new Response(null, { status: 200 }),
			nowUnixNano: (): string => {
				timestamp += 1_000_000n;
				return timestamp.toString();
			},
		});
		const operationId = 'a'.repeat(64);
		for (const phase of ['metadata_enqueue_started', 'metadata_enqueue_terminal'] as const) {
			expect(
				await sink.recordNativeObservation({
					scenario: 'lifecycle-proof',
					source: 'server',
					samples: [lifecycleSample(operationId, phase)],
				}),
			).toBe(true);
		}

		expect(sink.snapshot().operationLifecycle.completedOperationIds).toEqual([operationId]);
		expect(sink.snapshot().operationLifecycle.malformed).toEqual([]);
		expect(sink.snapshot().operationLifecycle.missingTerminals).toEqual([]);
	});
});

function lifecycleSample(operationId: string, phase: string): BridgeTelemetrySample {
	return {
		booleanAttributes: {},
		durationMilliseconds: null,
		name: 'performance.bridge.web.operation_lifecycle',
		numericAttributes: { 'agentstudio.bridge.stage.attempt': 0 },
		scope: 'web' as const,
		stringAttributes: {
			'agentstudio.bridge.operation.id': operationId,
			'agentstudio.bridge.phase': phase,
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.protocol': 'worktree-file',
			'agentstudio.bridge.result': phase.endsWith('_started') ? 'started' : 'success',
			'agentstudio.bridge.slice': 'content_fetch',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.viewer': 'file',
		},
		traceContext: null,
	};
}
