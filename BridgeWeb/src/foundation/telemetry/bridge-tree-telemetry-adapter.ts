import type { BridgeTelemetryRecorder } from './bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from './bridge-trace-context.js';

export type BridgeTreeTelemetryViewer = 'file' | 'review';
export type BridgeTreeTelemetryResult = 'failed' | 'success';
export type BridgeTreeClickSource = 'keyboard' | 'mouse' | 'programmatic';
export type BridgeTreeScrollOffset = 'nearest' | 'none' | 'top' | 'unknown';
export type BridgeTreeScrollReason =
	| 'anchor_workaround'
	| 'append_reveal'
	| 'clicked_selection'
	| 'search_match'
	| 'selected_path_effect'
	| 'selection_sync';
export type BridgeTreeAnchorRestorePhase =
	| 'capture'
	| 'direct_restore'
	| 'path_order_restore'
	| 'raf_restore'
	| 'scroll_to_path_reveal';

interface BridgeTreeTelemetryBaseProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
}

export interface BridgeTreeClickToRowHighlightTelemetrySampleProps extends BridgeTreeTelemetryBaseProps {
	readonly alreadySelected: boolean;
	readonly durationMilliseconds: number;
	readonly result: BridgeTreeTelemetryResult;
	readonly scrollActive: boolean;
	readonly source: BridgeTreeClickSource;
	readonly viewer: BridgeTreeTelemetryViewer;
	readonly visibleItemCount: number;
}

export interface BridgeTreeHoverToRenderTelemetrySampleProps extends BridgeTreeTelemetryBaseProps {
	readonly durationMilliseconds: number;
	readonly result: BridgeTreeTelemetryResult;
	readonly rowMounted: boolean;
	readonly viewer: BridgeTreeTelemetryViewer;
	readonly visibleItemCount: number;
}

export interface BridgeTreeScrollFrameGapTelemetrySampleProps extends BridgeTreeTelemetryBaseProps {
	readonly durationMilliseconds: number;
	readonly frameGapMaxMilliseconds: number;
	readonly frameGapP95Milliseconds: number;
	readonly framesOver16Milliseconds: number;
	readonly framesOver33Milliseconds: number;
	readonly framesOver50Milliseconds: number;
	readonly scheduledPublisherSkippedCount: number;
	readonly viewer: BridgeTreeTelemetryViewer;
	readonly visibleRowCount: number;
}

export interface BridgeTreeAnchorRestoreTelemetrySampleProps extends BridgeTreeTelemetryBaseProps {
	readonly callCount: number;
	readonly directScrollTopWriteCount: number;
	readonly durationMilliseconds: number;
	readonly phase: BridgeTreeAnchorRestorePhase;
	readonly syntheticScrollCount: number;
}

export interface BridgeTreeScrollToPathTelemetrySampleProps extends BridgeTreeTelemetryBaseProps {
	readonly durationMilliseconds: number;
	readonly focus: boolean;
	readonly offset: BridgeTreeScrollOffset;
	readonly reason: BridgeTreeScrollReason;
	readonly viewer: BridgeTreeTelemetryViewer;
}

export interface BridgeTreeVisibleIdsCaptureTelemetrySampleProps extends BridgeTreeTelemetryBaseProps {
	readonly durationMilliseconds: number;
	readonly returnedDescriptorCount: number;
	readonly returnedItemCount: number;
	readonly rowCount: number;
	readonly viewer: BridgeTreeTelemetryViewer;
}

export function recordBridgeTreeClickToRowHighlightTelemetrySample(
	props: BridgeTreeClickToRowHighlightTelemetrySampleProps,
): void {
	recordBridgeTreeTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		durationMilliseconds: props.durationMilliseconds,
		name: 'performance.bridge.trees.click_to_row_highlight',
		phase: 'click_to_row_highlight',
		viewer: props.viewer,
		stringAttributes: {
			'agentstudio.bridge.input.source': props.source,
			'agentstudio.bridge.result': props.result,
		},
		numericAttributes: {
			'agentstudio.bridge.visible_item.count': props.visibleItemCount,
		},
		booleanAttributes: {
			'agentstudio.bridge.already_selected': props.alreadySelected,
			'agentstudio.bridge.scroll.active': props.scrollActive,
		},
	});
}

export function recordBridgeTreeHoverToRenderTelemetrySample(
	props: BridgeTreeHoverToRenderTelemetrySampleProps,
): void {
	recordBridgeTreeTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		durationMilliseconds: props.durationMilliseconds,
		name: 'performance.bridge.trees.hover_to_render',
		phase: 'hover_to_render',
		viewer: props.viewer,
		stringAttributes: {
			'agentstudio.bridge.result': props.result,
		},
		numericAttributes: {
			'agentstudio.bridge.visible_item.count': props.visibleItemCount,
		},
		booleanAttributes: {
			'agentstudio.bridge.row_mounted': props.rowMounted,
		},
	});
}

export function recordBridgeTreeScrollFrameGapTelemetrySample(
	props: BridgeTreeScrollFrameGapTelemetrySampleProps,
): void {
	recordBridgeTreeTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		durationMilliseconds: props.durationMilliseconds,
		name: 'performance.bridge.trees.scroll_frame_gap',
		phase: 'scroll_frame_gap',
		viewer: props.viewer,
		stringAttributes: {
			'agentstudio.bridge.result': 'success',
		},
		numericAttributes: {
			'agentstudio.bridge.scroll.frame_gap.max_ms': props.frameGapMaxMilliseconds,
			'agentstudio.bridge.scroll.frame_gap.over_16ms.count': props.framesOver16Milliseconds,
			'agentstudio.bridge.scroll.frame_gap.over_33ms.count': props.framesOver33Milliseconds,
			'agentstudio.bridge.scroll.frame_gap.over_50ms.count': props.framesOver50Milliseconds,
			'agentstudio.bridge.scroll.frame_gap.p95_ms': props.frameGapP95Milliseconds,
			'agentstudio.bridge.visible_publisher.skipped.count': props.scheduledPublisherSkippedCount,
			'agentstudio.bridge.visible_row.count': props.visibleRowCount,
		},
		booleanAttributes: {},
	});
}

export function recordBridgeTreeAnchorRestoreTelemetrySample(
	props: BridgeTreeAnchorRestoreTelemetrySampleProps,
): void {
	recordBridgeTreeTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		durationMilliseconds: props.durationMilliseconds,
		name: 'performance.bridge.trees.anchor_restore',
		phase: 'anchor_restore',
		viewer: 'file',
		stringAttributes: {
			'agentstudio.bridge.anchor_restore.phase': props.phase,
			'agentstudio.bridge.result': 'success',
		},
		numericAttributes: {
			'agentstudio.bridge.anchor_restore.call.count': props.callCount,
			'agentstudio.bridge.anchor_restore.direct_scroll_top_write.count':
				props.directScrollTopWriteCount,
			'agentstudio.bridge.anchor_restore.synthetic_scroll.count': props.syntheticScrollCount,
		},
		booleanAttributes: {},
	});
}

export function recordBridgeTreeScrollToPathTelemetrySample(
	props: BridgeTreeScrollToPathTelemetrySampleProps,
): void {
	recordBridgeTreeTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		durationMilliseconds: props.durationMilliseconds,
		name: 'performance.bridge.trees.scroll_to_path',
		phase: 'scroll_to_path',
		viewer: props.viewer,
		stringAttributes: {
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.scroll.offset': props.offset,
			'agentstudio.bridge.scroll.reason': props.reason,
		},
		numericAttributes: {},
		booleanAttributes: {
			'agentstudio.bridge.focus': props.focus,
		},
	});
}

export function recordBridgeTreeVisibleIdsCaptureTelemetrySample(
	props: BridgeTreeVisibleIdsCaptureTelemetrySampleProps,
): void {
	recordBridgeTreeTelemetrySample({
		telemetryRecorder: props.telemetryRecorder,
		traceContext: props.traceContext,
		durationMilliseconds: props.durationMilliseconds,
		name: 'performance.bridge.trees.visible_ids_capture',
		phase: 'visible_ids_capture',
		viewer: props.viewer,
		stringAttributes: {
			'agentstudio.bridge.result': 'success',
		},
		numericAttributes: {
			'agentstudio.bridge.visible_descriptor.count': props.returnedDescriptorCount,
			'agentstudio.bridge.visible_item.count': props.returnedItemCount,
			'agentstudio.bridge.visible_row.count': props.rowCount,
		},
		booleanAttributes: {},
	});
}

function recordBridgeTreeTelemetrySample(props: {
	readonly booleanAttributes: Readonly<Record<string, boolean>>;
	readonly durationMilliseconds: number;
	readonly name: string;
	readonly numericAttributes: Readonly<Record<string, number>>;
	readonly phase: string;
	readonly stringAttributes: Readonly<Record<string, string>>;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly viewer: BridgeTreeTelemetryViewer;
}): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: props.name,
		durationMilliseconds: Math.max(0, props.durationMilliseconds),
		traceContext: props.traceContext,
		stringAttributes: {
			'agentstudio.bridge.phase': props.phase,
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.slice': 'tree_prepare_input',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.viewer': props.viewer,
			...props.stringAttributes,
		},
		numericAttributes: props.numericAttributes,
		booleanAttributes: props.booleanAttributes,
	});
	props.telemetryRecorder.flush();
}
