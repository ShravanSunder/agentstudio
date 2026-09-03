import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from '../../src/foundation/telemetry/bridge-telemetry-event.js';
import {
	bridgeOperationLifecyclePhaseFamilies,
	reduceBridgeOperationLifecycle,
} from './bridge-dev-operation-lifecycle-reducer.js';

describe('Bridge dev operation lifecycle reducer', () => {
	test('classifies the first expired unmatched start by phase family', () => {
		const operationId = 'a'.repeat(64);
		const result = reduceBridgeOperationLifecycle({
			nowUnixMilliseconds: 200,
			samples: [sample(operationId, 'metadata_enqueue_started', 0, 100)],
			terminalWindowMilliseconds: 50,
		});

		expect(result).toEqual({
			completedOperationIds: [],
			malformed: [],
			missingTerminals: [
				{ operationCorrelationId: operationId, phaseFamily: 'metadata_enqueue', stageAttempt: 0 },
			],
		});
	});

	test('accepts paired repeated attempts and rejects terminal-without-start and duplicate starts', () => {
		const operationId = 'b'.repeat(64);
		const valid = reduceBridgeOperationLifecycle({
			nowUnixMilliseconds: 130,
			samples: [
				sample(operationId, 'projection_query_started', 0, 100),
				sample(operationId, 'projection_query_terminal', 0, 110),
				sample(operationId, 'projection_query_started', 1, 120),
				sample(operationId, 'projection_query_terminal', 1, 125),
			],
			terminalWindowMilliseconds: 50,
		});
		expect(valid.malformed).toEqual([]);
		expect(valid.missingTerminals).toEqual([]);

		const malformed = reduceBridgeOperationLifecycle({
			nowUnixMilliseconds: 130,
			samples: [
				sample(operationId, 'metadata_delivery_terminal', 0, 100),
				sample(operationId, 'render_operation_started', 0, 110),
				sample(operationId, 'render_operation_started', 0, 115),
			],
			terminalWindowMilliseconds: 50,
		});
		expect(malformed.malformed.map((entry) => entry.kind)).toEqual([
			'terminal_without_start',
			'duplicate_start',
		]);
	});

	test('names every withheld terminal family and rejects bounded-capacity overflow', () => {
		for (const [ordinal, phaseFamily] of bridgeOperationLifecyclePhaseFamilies.entries()) {
			const operationId = ordinal.toString(16).padStart(64, '0');
			const result = reduceBridgeOperationLifecycle({
				nowUnixMilliseconds: 200,
				samples: [sample(operationId, `${phaseFamily}_started`, 0, 100)],
				terminalWindowMilliseconds: 50,
			});
			expect(result.missingTerminals).toEqual([
				{ operationCorrelationId: operationId, phaseFamily, stageAttempt: 0 },
			]);
		}

		const overflow = reduceBridgeOperationLifecycle({
			maximumTrackedStageAttempts: 1,
			nowUnixMilliseconds: 100,
			samples: [
				sample('a'.repeat(64), 'metadata_enqueue_started', 0, 100),
				sample('b'.repeat(64), 'metadata_enqueue_started', 0, 100),
			],
			terminalWindowMilliseconds: 50,
		});
		expect(overflow.malformed.map((entry) => entry.kind)).toContain('capacity_exceeded');
	});
});

function sample(
	operationCorrelationId: string,
	phase: string,
	stageAttempt: number,
	observedAtUnixMilliseconds: number,
): BridgeTelemetrySample & { readonly observedAtUnixMilliseconds: number } {
	return {
		booleanAttributes: {},
		durationMilliseconds: null,
		name: 'performance.bridge.web.operation_lifecycle',
		numericAttributes: { 'agentstudio.bridge.stage.attempt': stageAttempt },
		observedAtUnixMilliseconds,
		scope: 'web',
		stringAttributes: {
			'agentstudio.bridge.operation.id': operationCorrelationId,
			'agentstudio.bridge.phase': phase,
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.result': phase.endsWith('_started') ? 'started' : 'success',
			'agentstudio.bridge.slice': 'review_projection',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.viewer': 'review',
		},
		traceContext: null,
	};
}
