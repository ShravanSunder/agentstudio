import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeWorkerContentAvailabilityPatchPayload } from './bridge-worker-contracts.js';

export interface BridgeCommWorkerPerformanceClock {
	readonly timeOrigin: number;
	readonly now: () => number;
}

export type BridgeCommWorkerTelemetryTaskKind =
	| 'content_preparation'
	| 'message_handler'
	| 'store_action';

export type BridgeCommWorkerTelemetryLane =
	| 'background'
	| 'file_view'
	| 'nearby'
	| 'selected'
	| 'speculative'
	| 'visible';

export type BridgeCommWorkerTelemetryAction =
	| 'applyContentReady'
	| 'applyContentTerminalAvailability'
	| 'applyFileViewSourceMutationFact'
	| 'applyFileViewSourceUpdateFact'
	| 'applyReviewInvalidationFact'
	| 'applyReviewRowMutationFact'
	| 'applyReviewSourceUpdateFact'
	| 'applySelectedFact'
	| 'applySelectedSourceChurnFact'
	| 'applyViewportFact';

export type BridgeCommWorkerTelemetryCommand =
	| 'activeViewerModeUpdate'
	| 'fileDisplayResync'
	| 'fileQueryUpdate'
	| 'hover'
	| 'markFileViewed'
	| 'metadataInterestUpdate'
	| 'mode'
	| 'reviewIntakeReady'
	| 'reviewInvalidate'
	| 'renderDisposition'
	| 'select'
	| 'viewport';

export interface BridgeCommWorkerTelemetryRecorder {
	readonly record: (sample: BridgeTelemetrySample) => void;
}

export type BridgeCommWorkerSelectedContentDropReason =
	| 'stale_after_fetch'
	| 'stale_before_fetch'
	| 'stale_before_publish';

export function readBridgeCommWorkerAbsoluteNowMilliseconds(
	clock: BridgeCommWorkerPerformanceClock = performance,
): number {
	return clock.timeOrigin + clock.now();
}

export interface RecordBridgeCommWorkerTaskTelemetryProps {
	readonly action?: BridgeCommWorkerTelemetryAction;
	readonly command?: BridgeCommWorkerTelemetryCommand;
	readonly durationMilliseconds: number;
	readonly lane: BridgeCommWorkerTelemetryLane;
	readonly payloadClass?: string;
	readonly queueWaitMilliseconds?: number;
	readonly resultReason?: BridgeCommWorkerTelemetryResultReason;
	readonly sourceEpoch?: number;
	readonly taskKind: BridgeCommWorkerTelemetryTaskKind;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
	readonly touchedKeyCount?: number;
	readonly patchCount?: number;
	readonly workKind?: string;
}

export function recordBridgeCommWorkerTaskTelemetry(
	props: RecordBridgeCommWorkerTaskTelemetryProps,
): void {
	props.telemetryClient?.record({
		scope: 'web',
		name: 'performance.bridge.worker.task',
		durationMilliseconds: Math.max(0, props.durationMilliseconds),
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'worker_task',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': bridgeCommWorkerTaskPriority(props.lane),
			'agentstudio.bridge.result': 'success',
			'agentstudio.bridge.slice': 'worker_task',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': props.lane,
			'agentstudio.bridge.worker.task_kind': props.taskKind,
			...(props.action === undefined ? {} : { 'agentstudio.bridge.worker.action': props.action }),
			...(props.command === undefined
				? {}
				: { 'agentstudio.bridge.worker.command': props.command }),
			...(props.payloadClass === undefined
				? {}
				: { 'agentstudio.bridge.worker.payload_class': props.payloadClass }),
			...(props.resultReason === undefined
				? {}
				: { 'agentstudio.bridge.result_reason': props.resultReason }),
			...(props.workKind === undefined
				? {}
				: { 'agentstudio.bridge.worker.work_kind': props.workKind }),
		},
		numericAttributes: {
			'agentstudio.bridge.worker.handler_duration_ms': Math.max(0, props.durationMilliseconds),
			...(props.queueWaitMilliseconds === undefined
				? {}
				: {
						'agentstudio.bridge.worker.queue_wait_ms': Math.max(0, props.queueWaitMilliseconds),
					}),
			...(props.sourceEpoch === undefined
				? {}
				: { 'agentstudio.bridge.worker.source_epoch': props.sourceEpoch }),
			...(props.touchedKeyCount === undefined
				? {}
				: { 'agentstudio.bridge.worker.touched_key_count': props.touchedKeyCount }),
			...(props.patchCount === undefined
				? {}
				: { 'agentstudio.bridge.worker.patch_count': props.patchCount }),
		},
		booleanAttributes: {},
	});
}

export interface RecordBridgeCommWorkerSelectedContentDroppedTelemetryProps {
	readonly dropReason: BridgeCommWorkerSelectedContentDropReason;
	readonly telemetryClient?: BridgeCommWorkerTelemetryRecorder;
}

export function recordBridgeCommWorkerSelectedContentDroppedTelemetry(
	props: RecordBridgeCommWorkerSelectedContentDroppedTelemetryProps,
): void {
	props.telemetryClient?.record({
		scope: 'web',
		name: 'performance.bridge.web.selected_content_dropped',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.drop_reason': props.dropReason,
			'agentstudio.bridge.phase': 'selected_content_dropped',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'hot',
			'agentstudio.bridge.result': 'dropped',
			'agentstudio.bridge.slice': 'content_fetch',
			'agentstudio.bridge.transport': 'content',
			'agentstudio.bridge.viewer': 'review',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
}

type BridgeCommWorkerTelemetryResultReason = NonNullable<
	BridgeWorkerContentAvailabilityPatchPayload['reason']
>;

function bridgeCommWorkerTaskPriority(lane: BridgeCommWorkerTelemetryLane): string {
	return lane === 'selected' ? 'hot' : 'warm';
}
