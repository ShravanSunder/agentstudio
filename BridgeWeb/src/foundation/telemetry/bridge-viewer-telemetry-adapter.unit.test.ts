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
	recordBridgeTreeAnchorRestoreTelemetrySample,
	recordBridgeTreeClickToRowHighlightTelemetrySample,
	recordBridgeTreeHoverToRenderTelemetrySample,
	recordBridgeTreeScrollFrameGapTelemetrySample,
	recordBridgeTreeScrollToPathTelemetrySample,
	recordBridgeTreeVisibleIdsCaptureTelemetrySample,
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

describe('bridge tree telemetry adapter sample shapes', () => {
	test('records click_to_row_highlight with bounded interaction attributes', () => {
		const recorder = makeCapturingRecorder();

		recordBridgeTreeClickToRowHighlightTelemetrySample({
			alreadySelected: false,
			durationMilliseconds: 12,
			result: 'success',
			scrollActive: true,
			source: 'mouse',
			telemetryRecorder: recorder,
			traceContext: null,
			viewer: 'review',
			visibleItemCount: 18,
		});

		expect(recorder.samples).toEqual([
			expect.objectContaining({
				name: 'performance.bridge.trees.click_to_row_highlight',
				durationMilliseconds: 12,
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.input.source': 'mouse',
					'agentstudio.bridge.phase': 'click_to_row_highlight',
					'agentstudio.bridge.result': 'success',
					'agentstudio.bridge.viewer': 'review',
				}),
				numericAttributes: {
					'agentstudio.bridge.visible_item.count': 18,
				},
				booleanAttributes: {
					'agentstudio.bridge.already_selected': false,
					'agentstudio.bridge.scroll.active': true,
				},
			}),
		]);
	});

	test('records hover_to_render with row mount status', () => {
		const recorder = makeCapturingRecorder();

		recordBridgeTreeHoverToRenderTelemetrySample({
			durationMilliseconds: 7,
			result: 'success',
			rowMounted: true,
			telemetryRecorder: recorder,
			traceContext: null,
			viewer: 'review',
			visibleItemCount: 14,
		});

		expect(recorder.samples[0]).toMatchObject({
			name: 'performance.bridge.trees.hover_to_render',
			stringAttributes: {
				'agentstudio.bridge.phase': 'hover_to_render',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.slice': 'tree_prepare_input',
				'agentstudio.bridge.transport': 'worker',
				'agentstudio.bridge.viewer': 'review',
			},
			numericAttributes: {
				'agentstudio.bridge.visible_item.count': 14,
			},
			booleanAttributes: {
				'agentstudio.bridge.row_mounted': true,
			},
		});
	});

	test('records scroll_frame_gap with settle-only aggregate counters', () => {
		const recorder = makeCapturingRecorder();

		recordBridgeTreeScrollFrameGapTelemetrySample({
			durationMilliseconds: 64,
			frameGapMaxMilliseconds: 41,
			frameGapP95Milliseconds: 33,
			framesOver16Milliseconds: 3,
			framesOver33Milliseconds: 1,
			framesOver50Milliseconds: 0,
			scheduledPublisherSkippedCount: 2,
			telemetryRecorder: recorder,
			traceContext: null,
			viewer: 'review',
			visibleRowCount: 22,
		});

		expect(recorder.samples[0]).toMatchObject({
			name: 'performance.bridge.trees.scroll_frame_gap',
			durationMilliseconds: 64,
			numericAttributes: {
				'agentstudio.bridge.scroll.frame_gap.max_ms': 41,
				'agentstudio.bridge.scroll.frame_gap.p95_ms': 33,
				'agentstudio.bridge.scroll.frame_gap.over_16ms.count': 3,
				'agentstudio.bridge.scroll.frame_gap.over_33ms.count': 1,
				'agentstudio.bridge.scroll.frame_gap.over_50ms.count': 0,
				'agentstudio.bridge.visible_publisher.skipped.count': 2,
				'agentstudio.bridge.visible_row.count': 22,
			},
		});
	});

	test('records anchor_restore without path or item identifiers', () => {
		const recorder = makeCapturingRecorder();

		recordBridgeTreeAnchorRestoreTelemetrySample({
			callCount: 1,
			directScrollTopWriteCount: 1,
			durationMilliseconds: 4,
			phase: 'direct_restore',
			syntheticScrollCount: 1,
			telemetryRecorder: recorder,
			traceContext: null,
		});

		expect(recorder.samples[0]).toMatchObject({
			name: 'performance.bridge.trees.anchor_restore',
			stringAttributes: expect.objectContaining({
				'agentstudio.bridge.anchor_restore.phase': 'direct_restore',
				'agentstudio.bridge.phase': 'anchor_restore',
				'agentstudio.bridge.viewer': 'file',
			}),
			numericAttributes: {
				'agentstudio.bridge.anchor_restore.call.count': 1,
				'agentstudio.bridge.anchor_restore.direct_scroll_top_write.count': 1,
				'agentstudio.bridge.anchor_restore.synthetic_scroll.count': 1,
			},
		});
	});

	test('records scroll_to_path reason focus and offset without the target path', () => {
		const recorder = makeCapturingRecorder();

		recordBridgeTreeScrollToPathTelemetrySample({
			durationMilliseconds: 3,
			focus: true,
			offset: 'nearest',
			reason: 'selected_path_effect',
			telemetryRecorder: recorder,
			traceContext: null,
			viewer: 'file',
		});

		expect(recorder.samples[0]).toMatchObject({
			name: 'performance.bridge.trees.scroll_to_path',
			stringAttributes: expect.objectContaining({
				'agentstudio.bridge.phase': 'scroll_to_path',
				'agentstudio.bridge.scroll.offset': 'nearest',
				'agentstudio.bridge.scroll.reason': 'selected_path_effect',
				'agentstudio.bridge.viewer': 'file',
			}),
			numericAttributes: {},
			booleanAttributes: {
				'agentstudio.bridge.focus': true,
			},
		});
	});

	test('records visible_ids_capture returned counts without row ids or paths', () => {
		const recorder = makeCapturingRecorder();

		recordBridgeTreeVisibleIdsCaptureTelemetrySample({
			durationMilliseconds: 5,
			returnedDescriptorCount: 4,
			returnedItemCount: 6,
			rowCount: 9,
			telemetryRecorder: recorder,
			traceContext: null,
			viewer: 'review',
		});

		expect(recorder.samples[0]).toMatchObject({
			name: 'performance.bridge.trees.visible_ids_capture',
			stringAttributes: expect.objectContaining({
				'agentstudio.bridge.phase': 'visible_ids_capture',
				'agentstudio.bridge.viewer': 'review',
			}),
			numericAttributes: {
				'agentstudio.bridge.visible_descriptor.count': 4,
				'agentstudio.bridge.visible_item.count': 6,
				'agentstudio.bridge.visible_row.count': 9,
			},
		});
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
