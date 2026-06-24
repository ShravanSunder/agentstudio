import type { BridgeTelemetryRecorder } from './bridge-telemetry-recorder.js';
import type { BridgeTraceContext } from './bridge-trace-context.js';

export interface BridgeProjectionBuildTelemetrySampleProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly durationMilliseconds: number | null;
	readonly executionLane: 'sync' | 'worker';
	readonly fixtureClass: 'smoke' | 'medium' | 'large' | 'huge';
	readonly itemCountBucket: 'empty' | 'small' | 'medium' | 'large' | 'huge';
	readonly projectionKind: string;
	readonly treePathCountBucket: 'empty' | 'small' | 'medium' | 'large' | 'huge';
}

export interface BridgeViewerContentQueueTelemetrySampleProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly contentRole: 'base' | 'head' | 'diff' | 'file' | 'unknown';
	readonly interest: 'selected' | 'visible' | 'nearby' | 'speculative';
}

export interface BridgeViewerContentFetchTelemetrySampleProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly contentRole: 'base' | 'head' | 'diff' | 'file' | 'unknown';
	readonly durationMilliseconds: number;
	readonly interest: 'selected' | 'visible' | 'nearby' | 'speculative';
	readonly result: 'success' | 'deferred' | 'failed';
	readonly resultReason: string | null;
}

export interface BridgeCodeViewHydrationTelemetrySampleProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly traceContext: BridgeTraceContext | null;
	readonly contentBytesBucket: 'empty' | 'small' | 'medium' | 'large' | 'huge';
	readonly itemCountBucket: 'empty' | 'small' | 'medium' | 'large' | 'huge';
	readonly languageClass: 'config' | 'markdown' | 'other' | 'swift' | 'text' | 'typescript';
	readonly workerLane: 'none' | 'pierre';
}

export function recordBridgeProjectionBuildTelemetrySample(
	props: BridgeProjectionBuildTelemetrySampleProps,
): void {
	recordWhenEnabled(props.telemetryRecorder, () => {
		props.telemetryRecorder.record({
			scope: 'web',
			name: 'performance.bridge.trees.projection_build',
			durationMilliseconds: props.durationMilliseconds,
			traceContext: props.traceContext,
			stringAttributes: {
				'agentstudio.bridge.fixture_class': props.fixtureClass,
				'agentstudio.bridge.item_count_bucket': props.itemCountBucket,
				'agentstudio.bridge.phase': 'projection_build',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'warm',
				'agentstudio.bridge.projection.kind': props.projectionKind,
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.slice': 'review_projection',
				'agentstudio.bridge.transport': 'worker',
				'agentstudio.bridge.tree_path_count_bucket': props.treePathCountBucket,
				'agentstudio.bridge.worker.lane': props.executionLane === 'worker' ? 'projection' : 'none',
			},
			numericAttributes: {},
			booleanAttributes: {},
		});
	});
}

export function recordBridgeViewerContentQueueTelemetrySample(
	props: BridgeViewerContentQueueTelemetrySampleProps,
): void {
	recordWhenEnabled(props.telemetryRecorder, () => {
		props.telemetryRecorder.record({
			scope: 'web',
			name: 'performance.bridge.viewer.content_queue',
			durationMilliseconds: null,
			traceContext: props.traceContext,
			stringAttributes: {
				'agentstudio.bridge.content.interest': props.interest,
				'agentstudio.bridge.content.priority': props.interest,
				'agentstudio.bridge.content.role': props.contentRole,
				'agentstudio.bridge.phase': 'content_queue',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.queue.depth_bucket': 'small',
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.slice': 'content_fetch',
				'agentstudio.bridge.transport': 'content',
			},
			numericAttributes: {},
			booleanAttributes: {},
		});
	});
}

export function recordBridgeViewerContentFetchTelemetrySample(
	props: BridgeViewerContentFetchTelemetrySampleProps,
): void {
	recordWhenEnabled(props.telemetryRecorder, () => {
		props.telemetryRecorder.record({
			scope: 'web',
			name: 'performance.bridge.web.content_fetch',
			durationMilliseconds: props.durationMilliseconds,
			traceContext: props.traceContext,
			stringAttributes: {
				'agentstudio.bridge.content.correlation_mode': 'summary',
				'agentstudio.bridge.content.interest': props.interest,
				'agentstudio.bridge.content.role': props.contentRole,
				'agentstudio.bridge.phase': 'fetch',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.result': props.result,
				'agentstudio.bridge.result_reason': props.resultReason ?? 'none',
				'agentstudio.bridge.slice': 'content_fetch',
				'agentstudio.bridge.transport': 'content',
			},
			numericAttributes: {},
			booleanAttributes: {
				'agentstudio.bridge.header_missing': true,
				'agentstudio.bridge.header_supported': false,
			},
		});
		props.telemetryRecorder.flush();
	});
}

export function recordBridgeCodeViewHydrationTelemetrySamples(
	props: BridgeCodeViewHydrationTelemetrySampleProps,
): void {
	recordWhenEnabled(props.telemetryRecorder, () => {
		props.telemetryRecorder.record({
			scope: 'web',
			name: 'performance.bridge.pierre.item_update',
			durationMilliseconds: null,
			traceContext: props.traceContext,
			stringAttributes: {
				'agentstudio.bridge.item_count_bucket': props.itemCountBucket,
				'agentstudio.bridge.item_update.kind': 'hydrate',
				'agentstudio.bridge.phase': 'item_update',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.slice': 'code_view_item',
				'agentstudio.bridge.transport': 'swift',
			},
			numericAttributes: {},
			booleanAttributes: {},
		});
		props.telemetryRecorder.record({
			scope: 'web',
			name: 'performance.bridge.shiki.highlight',
			durationMilliseconds: null,
			traceContext: props.traceContext,
			stringAttributes: {
				'agentstudio.bridge.content_bytes_bucket': props.contentBytesBucket,
				'agentstudio.bridge.language_class': props.languageClass,
				'agentstudio.bridge.phase': 'highlight',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.slice': 'shiki_highlight',
				'agentstudio.bridge.transport': 'worker',
				'agentstudio.bridge.worker.lane': props.workerLane,
			},
			numericAttributes: {},
			booleanAttributes: {},
		});
		props.telemetryRecorder.record({
			scope: 'web',
			name: 'performance.bridge.worker.task',
			durationMilliseconds: null,
			traceContext: props.traceContext,
			stringAttributes: {
				'agentstudio.bridge.item_count_bucket': props.itemCountBucket,
				'agentstudio.bridge.phase': 'worker_task',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'warm',
				'agentstudio.bridge.result': 'success',
				'agentstudio.bridge.slice': 'worker_task',
				'agentstudio.bridge.transport': 'worker',
				'agentstudio.bridge.worker.lane': props.workerLane,
				'agentstudio.bridge.worker.task_kind': 'highlight',
			},
			numericAttributes: {},
			booleanAttributes: {},
		});
		props.telemetryRecorder.flush({ force: true });
	});
}

function recordWhenEnabled(telemetryRecorder: BridgeTelemetryRecorder, record: () => void): void {
	if (!telemetryRecorder.isEnabled('web')) {
		return;
	}
	record();
}
