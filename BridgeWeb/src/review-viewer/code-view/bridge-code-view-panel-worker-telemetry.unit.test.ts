import { describe, expect, test } from 'vitest';

import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { materializeBridgeCodeViewLoadingItem } from './bridge-code-view-materialization.js';
import { recordBridgeWorkerPreparedCodeViewItemMaterializeTelemetryForPanel } from './bridge-code-view-panel-support.js';

describe('BridgeCodeViewPanel worker telemetry', () => {
	test('emits worker transport materialize telemetry for worker-prepared item applies', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		if (item === undefined) {
			throw new Error('Expected modified item');
		}
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const workerPreparedItem = materializeBridgeCodeViewLoadingItem(item);
		const samples: BridgeTelemetrySample[] = [];

		recordBridgeWorkerPreparedCodeViewItemMaterializeTelemetryForPanel({
			codeViewItem: workerPreparedItem,
			durationMilliseconds: 6,
			item,
			parentTraceContext: null,
			projection,
			result: 'updated',
			selectedItemId: item.itemId,
			telemetryRecorder: enabledTelemetryRecorder(samples),
		});

		expect(samples).toHaveLength(1);
		expect(samples[0]).toMatchObject({
			name: 'performance.bridge.web.code_view_item_materialize',
			stringAttributes: {
				'agentstudio.bridge.transport': 'worker',
			},
			booleanAttributes: {
				'agentstudio.bridge.selected': true,
			},
		});
	});

	test('does not emit materialize telemetry for unchanged worker-prepared no-ops', () => {
		const reviewPackage = makeBridgeReviewPackage();
		const item = reviewPackage.itemsById['item-source'];
		if (item === undefined) {
			throw new Error('Expected modified item');
		}
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { mode: { kind: 'normalReview' }, facets: [] },
		});
		const workerPreparedItem = materializeBridgeCodeViewLoadingItem(item);
		const samples: BridgeTelemetrySample[] = [];

		recordBridgeWorkerPreparedCodeViewItemMaterializeTelemetryForPanel({
			codeViewItem: workerPreparedItem,
			durationMilliseconds: 0,
			item,
			parentTraceContext: null,
			projection,
			result: 'unchanged',
			selectedItemId: item.itemId,
			telemetryRecorder: enabledTelemetryRecorder(samples),
		});

		expect(samples).toEqual([]);
	});
});

function enabledTelemetryRecorder(samples: BridgeTelemetrySample[]): BridgeTelemetryRecorder {
	return {
		isEnabled: (scope): boolean => scope === 'web',
		record: (sample): void => {
			samples.push(sample);
		},
		measure: <TResult>(props: { readonly operation: () => TResult }): TResult => props.operation(),
		flush: (): boolean => true,
	};
}
