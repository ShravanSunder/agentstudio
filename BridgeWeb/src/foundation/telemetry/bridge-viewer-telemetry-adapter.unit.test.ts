import { afterEach, describe, expect, test, vi } from 'vitest';

import type { BridgeTelemetrySample } from './bridge-telemetry-event.js';
import type {
	BridgeTelemetryMeasureProps,
	BridgeTelemetryRecorder,
} from './bridge-telemetry-recorder.js';
import {
	recordBridgeCodeViewHydrationTelemetrySamples,
	recordBridgeFrameJankTelemetrySample,
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

afterEach(() => {
	vi.useRealTimers();
});

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
			transport: 'swift',
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

	test('does not force-flush tree hot-path samples per record', () => {
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

		expect(recorder.samples.map((sample) => sample.name)).toEqual([
			'performance.bridge.trees.click_to_row_highlight',
		]);
		expect(recorder.flushForces).toEqual([]);
	});

	test('summarizes hover_to_render bursts after settle', async () => {
		vi.useFakeTimers();
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
		recordBridgeTreeHoverToRenderTelemetrySample({
			durationMilliseconds: 13,
			result: 'failed',
			rowMounted: false,
			telemetryRecorder: recorder,
			traceContext: null,
			viewer: 'review',
			visibleItemCount: 16,
		});
		recordBridgeTreeHoverToRenderTelemetrySample({
			durationMilliseconds: 21,
			result: 'success',
			rowMounted: true,
			telemetryRecorder: recorder,
			traceContext: null,
			viewer: 'review',
			visibleItemCount: 15,
		});

		expect(recorder.samples).toEqual([]);

		await vi.advanceTimersByTimeAsync(50);

		expect(recorder.samples).toEqual([
			expect.objectContaining({
				name: 'performance.bridge.trees.hover_to_render',
				durationMilliseconds: 21,
				stringAttributes: expect.objectContaining({
					'agentstudio.bridge.phase': 'hover_to_render',
					'agentstudio.bridge.result': 'failed',
					'agentstudio.bridge.viewer': 'review',
				}),
				numericAttributes: {
					'agentstudio.bridge.hover_to_render.max_ms': 21,
					'agentstudio.bridge.hover_to_render.p95_ms': 21,
					'agentstudio.bridge.hover_to_render.sample.count': 3,
					'agentstudio.bridge.visible_item.count': 16,
				},
				booleanAttributes: {
					'agentstudio.bridge.row_mounted': false,
				},
			}),
		]);
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

	test('records hover_to_render summary with row mount status', async () => {
		vi.useFakeTimers();
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

		await vi.advanceTimersByTimeAsync(50);

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
				'agentstudio.bridge.hover_to_render.max_ms': 7,
				'agentstudio.bridge.hover_to_render.p95_ms': 7,
				'agentstudio.bridge.hover_to_render.sample.count': 1,
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

	test('records frame_jank as browser-local main-thread pressure telemetry', () => {
		const recorder = makeCapturingRecorder();

		recordBridgeFrameJankTelemetrySample({
			droppedFrameCount: 3,
			droppedFrameWorstGapMilliseconds: 72,
			durationMilliseconds: 72,
			kind: 'dropped_frame',
			longTaskCount: 2,
			longTaskMaxMilliseconds: 54,
			longTaskTotalMilliseconds: 94,
			telemetryRecorder: recorder,
			traceContext: null,
			viewer: 'review',
			viewerIsActive: false,
		});

		expect(recorder.samples[0]).toMatchObject({
			name: 'performance.bridge.web.frame_jank',
			durationMilliseconds: 72,
			stringAttributes: {
				'agentstudio.bridge.frame_jank.kind': 'dropped_frame',
				'agentstudio.bridge.phase': 'frame_jank',
				'agentstudio.bridge.plane': 'control',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.slice': 'frame_jank',
				'agentstudio.bridge.transport': 'local',
				'agentstudio.bridge.viewer': 'review',
			},
			numericAttributes: {
				'agentstudio.bridge.frame_jank.dropped_frame.count': 3,
				'agentstudio.bridge.frame_jank.dropped_frame.worst_gap_ms': 72,
				'agentstudio.bridge.frame_jank.long_task.count': 2,
				'agentstudio.bridge.frame_jank.long_task.max_ms': 54,
				'agentstudio.bridge.frame_jank.long_task.total_ms': 94,
			},
			booleanAttributes: {
				'agentstudio.bridge.viewer.active': false,
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
