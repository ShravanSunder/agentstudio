import { describe, expect, test } from 'vitest';

import type { BridgeTelemetrySample } from './bridge-telemetry-event.js';
import type {
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from './bridge-telemetry-recorder.js';
import {
	recordBridgeCodeViewHydrationTelemetrySamples,
	recordBridgeSelectedContentDroppedTelemetrySample,
	recordBridgeSelectedContentPaintedTelemetrySample,
	recordBridgeViewerFirstInteractionReadyTelemetrySample,
} from './bridge-viewer-telemetry-adapter.js';

describe('bridge viewer telemetry adapter flushing', () => {
	test('uses idle-scheduled flushing for hot interaction samples', () => {
		const recorder = makeCapturingRecorder();

		recordBridgeViewerFirstInteractionReadyTelemetrySample({
			durationMilliseconds: 42,
			telemetryRecorder: recorder,
			traceContext: null,
			variant: 'cold',
			viewer: 'review',
			visibleItemCount: 12,
		});
		recordBridgeCodeViewHydrationTelemetrySamples({
			contentBytesBucket: 'medium',
			itemCountBucket: 'small',
			languageClass: 'typescript',
			telemetryRecorder: recorder,
			traceContext: null,
			workerLane: 'pierre',
		});
		recordBridgeSelectedContentPaintedTelemetrySample({
			clickToPaintMilliseconds: 24,
			frameWaitMilliseconds: 8,
			materializeMilliseconds: 11,
			telemetryRecorder: recorder,
			traceContext: null,
			viewer: 'review',
		});
		recordBridgeSelectedContentDroppedTelemetrySample({
			dropReason: 'superseded',
			telemetryRecorder: recorder,
			traceContext: null,
			viewer: 'review',
		});

		expect(recorder.samples.map((sample) => sample.name)).toEqual([
			'performance.bridge.viewer.time_to_first_interaction',
			'performance.bridge.pierre.item_update',
			'performance.bridge.shiki.highlight',
			'performance.bridge.worker.task',
			'performance.bridge.web.selected_content_painted',
			'performance.bridge.web.selected_content_dropped',
		]);
		expect(recorder.flushForces).toEqual([undefined, undefined, undefined, undefined]);
	});
});

function makeCapturingRecorder(): BridgeTelemetryRecorder & {
	readonly flushForces: Array<boolean | undefined>;
	readonly samples: BridgeTelemetrySample[];
} {
	const flushForces: Array<boolean | undefined> = [];
	const samples: BridgeTelemetrySample[] = [];
	return {
		flushForces,
		isEnabled: (): boolean => true,
		measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => props.operation(),
		record: (sample: BridgeTelemetrySample): void => {
			samples.push(sample);
		},
		samples,
		flush: (props): boolean => {
			flushForces.push(props?.force);
			return true;
		},
	};
}
