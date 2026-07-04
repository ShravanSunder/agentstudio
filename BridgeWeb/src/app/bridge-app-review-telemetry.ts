import type { BridgePushEnvelope } from '../bridge/bridge-push-envelope.js';
import type { BridgePushDropReason } from '../bridge/bridge-push-receiver.js';
import type { BridgeIntakeCarrierDrop } from '../core/intake/bridge-intake-carrier.js';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import type { ReviewProtocolFrame } from '../features/review/models/review-protocol-models.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetryRecorder } from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	planeForBridgeTelemetrySlice,
	priorityForBridgeTelemetrySlice,
	type BridgeTelemetryPriority,
	type BridgeTelemetrySlice,
} from '../foundation/telemetry/bridge-telemetry-taxonomy.js';
import {
	createBridgeChildTraceContext,
	type BridgeTraceContext,
} from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeMarkdownPreviewFallbackReason } from '../review-viewer/markdown/bridge-markdown-render-mode.js';
import { bridgeMarkdownPreviewMaxBytes } from '../review-viewer/markdown/bridge-markdown-render-mode.js';
import type { BridgeMarkdownRenderWorkerClientCompletion } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';

export interface BridgeReviewPackageTelemetryContext {
	readonly slice: BridgeTelemetrySlice;
	readonly traceContext: BridgeTraceContext | null;
	readonly transport: 'intake' | 'push';
}

export interface PendingReviewSelectionCommitTelemetry {
	readonly itemId: string;
	readonly packageKey: string;
	readonly startedAtMilliseconds: number;
	readonly traceContext: BridgeTraceContext | null;
}

export type BridgeReviewStartupTelemetryPhase =
	| 'review_metadata_apply'
	| 'review_ready'
	| 'selection_commit'
	| 'selected_content_ready';

export type MarkdownPreviewFallbackTelemetryReason =
	| BridgeMarkdownPreviewFallbackReason
	| 'workerUnavailable';

export function createChildTraceContext(
	parent: BridgeTraceContext | null,
): BridgeTraceContext | null {
	return parent === null ? null : createBridgeChildTraceContext(parent);
}

export function makeTelemetryMarkedItemKey(
	reviewPackage: BridgeReviewPackage,
	itemId: string,
): string {
	return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}:${itemId}`;
}

export function makeTelemetryPackageKey(reviewPackage: BridgeReviewPackage): string {
	return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}`;
}

interface RecordMarkdownRenderQueueTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
}

export function recordMarkdownRenderQueueTelemetry(
	props: RecordMarkdownRenderQueueTelemetryProps,
): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.markdown.render_queue',
		durationMilliseconds: null,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.phase': 'markdown_queue',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': 'queued',
			'agentstudio.bridge.slice': 'markdown_preview',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
}

interface RecordMarkdownRenderCompletionTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly completion: BridgeMarkdownRenderWorkerClientCompletion;
}

export function recordMarkdownRenderCompletionTelemetry(
	props: RecordMarkdownRenderCompletionTelemetryProps,
): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	const durationMilliseconds =
		props.completion.status === 'success'
			? props.completion.response.metrics.durationMilliseconds
			: null;
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.markdown.render',
		durationMilliseconds,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.content_bytes_bucket':
				props.completion.status === 'success'
					? byteCountBucket(props.completion.response.metrics.inputBytes)
					: 'unknown',
			'agentstudio.bridge.phase': 'markdown_render',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': props.completion.status,
			'agentstudio.bridge.slice': 'markdown_preview',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
		},
		numericAttributes:
			props.completion.status === 'success'
				? {
						'agentstudio.bridge.markdown.input_bytes': props.completion.response.metrics.inputBytes,
						'agentstudio.bridge.markdown.output_bytes':
							props.completion.response.metrics.outputBytes,
					}
				: {},
		booleanAttributes: {},
	});
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.worker.task',
		durationMilliseconds,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.phase': 'worker_task',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': props.completion.status,
			'agentstudio.bridge.slice': 'worker_task',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
			'agentstudio.bridge.worker.task_kind': 'markdown_render',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
	props.telemetryRecorder.flush();
}

interface RecordMarkdownPreviewFallbackTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly reason: MarkdownPreviewFallbackTelemetryReason;
}

export function recordMarkdownPreviewFallbackTelemetry(
	props: RecordMarkdownPreviewFallbackTelemetryProps,
): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.markdown.fallback',
		durationMilliseconds: null,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.markdown.fallback_reason': props.reason,
			'agentstudio.bridge.phase': 'markdown_decision',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': 'fallback',
			'agentstudio.bridge.slice': 'markdown_preview',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
}

export function isOversizedMarkdownPreviewOutput(html: string): boolean {
	return new TextEncoder().encode(html).byteLength > bridgeMarkdownPreviewMaxBytes;
}

function byteCountBucket(byteCount: number): 'empty' | 'small' | 'medium' | 'large' | 'huge' {
	if (byteCount <= 0) {
		return 'empty';
	}
	if (byteCount <= 32_768) {
		return 'small';
	}
	if (byteCount <= 512_000) {
		return 'medium';
	}
	if (byteCount <= 5_000_000) {
		return 'large';
	}
	return 'huge';
}

export function recordIntakeApplyTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
	envelope: BridgePushEnvelope,
): void {
	recordIntakeApplyTelemetryForSlice({
		telemetryRecorder,
		slice: envelope.slice,
		traceContext: envelope.traceContext,
		transport: 'push',
	});
}

export function recordIntakeApplyTelemetryForSlice(props: {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly slice: BridgeTelemetrySlice;
	readonly traceContext: BridgeTraceContext | null;
	readonly transport: 'intake' | 'push';
}): void {
	const eventName =
		props.transport === 'push'
			? 'performance.bridge.web.push_apply'
			: 'performance.bridge.web.intake_apply';
	props.telemetryRecorder.record({
		scope: 'web',
		name: eventName,
		durationMilliseconds: null,
		traceContext: props.traceContext,
		stringAttributes: {
			'agentstudio.bridge.phase': 'apply',
			'agentstudio.bridge.plane': planeForBridgeTelemetrySlice(props.slice),
			'agentstudio.bridge.priority': priorityForBridgeTelemetrySlice(props.slice),
			'agentstudio.bridge.slice': props.slice,
			'agentstudio.bridge.transport': props.transport,
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
	props.telemetryRecorder.flush();
}

export function recordReviewStartupTelemetry(props: {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly phase: BridgeReviewStartupTelemetryPhase;
	readonly slice: BridgeTelemetrySlice;
	readonly transport: 'content' | 'intake' | 'push' | 'worker';
	readonly traceContext: BridgeTraceContext | null;
	readonly durationMilliseconds: number | null;
	readonly result: 'failed' | 'success';
	readonly resultReason?: string;
	readonly numericAttributes?: Readonly<Record<string, number>>;
}): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: `performance.bridge.web.${props.phase}`,
		durationMilliseconds:
			props.durationMilliseconds === null ? null : Math.max(0, props.durationMilliseconds),
		traceContext: props.traceContext,
		stringAttributes: {
			'agentstudio.bridge.phase': props.phase,
			'agentstudio.bridge.plane': planeForBridgeTelemetrySlice(props.slice),
			'agentstudio.bridge.priority': priorityForBridgeStartupTelemetryPhase(props.phase),
			'agentstudio.bridge.result': props.result,
			'agentstudio.bridge.result_reason': props.resultReason ?? 'none',
			'agentstudio.bridge.slice': props.slice,
			'agentstudio.bridge.transport': props.transport,
		},
		numericAttributes: props.numericAttributes ?? {},
		booleanAttributes: {},
	});
	props.telemetryRecorder.flush();
}

function priorityForBridgeStartupTelemetryPhase(
	phase: BridgeReviewStartupTelemetryPhase,
): BridgeTelemetryPriority {
	switch (phase) {
		case 'selection_commit':
			return 'warm';
		case 'review_metadata_apply':
		case 'review_ready':
		case 'selected_content_ready':
			return 'hot';
	}
}

export function recordPushDropTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
	reason: BridgePushDropReason,
): void {
	if (reason === 'stale_push') {
		recordStalePushDropTelemetry(telemetryRecorder);
		return;
	}
	flushPendingStalePushDropTelemetry(telemetryRecorder);
	recordPushDropTelemetrySample({
		droppedCount: 1,
		reason,
		telemetryRecorder,
	});
	telemetryRecorder.flush();
}

interface PendingStalePushDropTelemetry {
	count: number;
	scheduled: boolean;
}

const pendingStalePushDropTelemetryByRecorder = new WeakMap<
	BridgeTelemetryRecorder,
	PendingStalePushDropTelemetry
>();

function recordStalePushDropTelemetry(telemetryRecorder: BridgeTelemetryRecorder): void {
	const pending = pendingStalePushDropTelemetryByRecorder.get(telemetryRecorder) ?? {
		count: 0,
		scheduled: false,
	};
	pending.count += 1;
	if (!pending.scheduled) {
		pending.scheduled = true;
		queueMicrotask((): void => {
			flushPendingStalePushDropTelemetry(telemetryRecorder);
		});
	}
	pendingStalePushDropTelemetryByRecorder.set(telemetryRecorder, pending);
}

function flushPendingStalePushDropTelemetry(telemetryRecorder: BridgeTelemetryRecorder): void {
	const pending = pendingStalePushDropTelemetryByRecorder.get(telemetryRecorder);
	if (pending === undefined || pending.count === 0) {
		return;
	}
	const droppedCount = pending.count;
	pending.count = 0;
	pending.scheduled = false;
	recordPushDropTelemetrySample({
		droppedCount,
		reason: 'stale_push',
		telemetryRecorder,
	});
	telemetryRecorder.flush();
}

function recordPushDropTelemetrySample(props: {
	readonly droppedCount: number;
	readonly reason: BridgePushDropReason;
	readonly telemetryRecorder: BridgeTelemetryRecorder;
}): void {
	const { droppedCount, reason, telemetryRecorder } = props;
	telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.telemetry_drop',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'dropped',
			'agentstudio.bridge.plane': 'observability',
			'agentstudio.bridge.priority': 'best_effort',
			'agentstudio.bridge.slice': 'telemetry_drop',
			'agentstudio.bridge.telemetry.drop_reason': reason,
			'agentstudio.bridge.transport': 'rpc',
		},
		numericAttributes: {
			'agentstudio.bridge.telemetry.dropped_count': droppedCount,
		},
		booleanAttributes: {},
	});
}

export function recordReviewIntakeDropTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
	drop: BridgeIntakeCarrierDrop,
): void {
	recordReviewIntakeFrameTelemetry({
		telemetryRecorder,
		frameKind:
			drop.reason === 'receiver_rejected_frame'
				? intakeTelemetryKindForFrameSummary(drop.frame.kind)
				: 'unknown',
		generation: drop.reason === 'receiver_rejected_frame' ? drop.frame.generation : 0,
		sequence: drop.reason === 'receiver_rejected_frame' ? drop.frame.sequence : 0,
		result: 'dropped',
		resultReason: drop.reason === 'receiver_rejected_frame' ? drop.receiverReason : drop.reason,
	});
}

export function recordReviewIntakeFrameTelemetry(props: {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly frameKind: ReviewProtocolFrame['frameKind'] | 'unknown';
	readonly generation: number;
	readonly sequence: number;
	readonly result: 'dropped' | 'failed' | 'success';
	readonly resultReason: string;
}): void {
	const slice = reviewIntakeTelemetrySliceForFrameKind(props.frameKind);
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.intake_frame',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.intake.frame_kind': props.frameKind,
			'agentstudio.bridge.phase': 'intake',
			'agentstudio.bridge.plane': planeForBridgeTelemetrySlice(slice),
			'agentstudio.bridge.priority': priorityForBridgeTelemetrySlice(slice),
			'agentstudio.bridge.result': props.result,
			'agentstudio.bridge.result_reason': props.resultReason,
			'agentstudio.bridge.slice': slice,
			'agentstudio.bridge.transport': 'intake',
		},
		numericAttributes: {
			'agentstudio.bridge.intake.generation': props.generation,
			'agentstudio.bridge.intake.sequence': props.sequence,
		},
		booleanAttributes: {},
	});
	props.telemetryRecorder.flush();
}

export function reviewIntakeTelemetrySliceForFrameKind(
	frameKind: ReviewProtocolFrame['frameKind'] | 'unknown',
): BridgeTelemetrySlice {
	switch (frameKind) {
		case 'review.metadataSnapshot':
		case 'review.metadataWindow':
			return 'review_metadata';
		case 'review.metadataDelta':
			return 'review_delta';
		case 'review.invalidate':
			return 'review_invalidation';
		case 'review.reset':
			return 'review_reset';
		case 'unknown':
			return 'review_projection';
	}
	return 'review_projection';
}

function intakeTelemetryKindForFrameSummary(
	frameKind: BridgeIntakeFrame['kind'],
): ReviewProtocolFrame['frameKind'] | 'unknown' {
	switch (frameKind) {
		case 'snapshot':
			return 'review.metadataSnapshot';
		case 'delta':
			return 'review.metadataDelta';
		case 'invalidate':
			return 'review.invalidate';
		case 'reset':
			return 'review.reset';
		case 'close':
		case 'error':
			return 'unknown';
	}
	return 'unknown';
}
