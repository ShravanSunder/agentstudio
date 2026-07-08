import type { BridgeTelemetryBootstrapConfig } from '../../foundation/telemetry/bridge-telemetry-bootstrap-config.js';
import {
	createBridgeTelemetryBuffer,
	type BridgeTelemetryDropCounter,
} from '../../foundation/telemetry/bridge-telemetry-buffer.js';
import {
	makeBridgeTelemetryBatch,
	type BridgeTelemetrySample,
} from '../../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetryScope } from '../../foundation/telemetry/bridge-telemetry-scope.js';
import {
	nullBridgeTelemetrySink,
	type BridgeTelemetrySink,
} from '../../foundation/telemetry/bridge-telemetry-sink.js';
import type { BridgeWorkerContentAvailabilityPatchPayload } from './bridge-worker-contracts.js';

type BridgeCommWorkerTelemetryIdleFlushScheduler = (callback: () => void) => void;

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

export interface BridgeCommWorkerTelemetryRecorder {
	readonly record: (sample: BridgeTelemetrySample) => void;
}

export interface BridgeCommWorkerTelemetryTransport {
	readonly endpointUrl: string;
}

export interface BridgeCommWorkerTelemetryClient extends BridgeCommWorkerTelemetryRecorder {
	readonly record: (sample: BridgeTelemetrySample) => void;
	readonly flush: () => boolean;
	readonly isEnabled: (scope: BridgeTelemetryScope) => boolean;
	readonly transport: BridgeCommWorkerTelemetryTransport;
}

export interface CreateBridgeCommWorkerTelemetryClientProps {
	readonly config: BridgeTelemetryBootstrapConfig;
	readonly sink?: BridgeTelemetrySink;
	readonly scheduleIdleFlush?: BridgeCommWorkerTelemetryIdleFlushScheduler;
}

export function createBridgeCommWorkerTelemetryClient(
	props: CreateBridgeCommWorkerTelemetryClientProps,
): BridgeCommWorkerTelemetryClient {
	const buffer = createBridgeTelemetryBuffer({
		maxSamplesPerBatch: props.config.maxSamplesPerBatch,
		maxEncodedBatchBytes: props.config.maxEncodedBatchBytes,
	});
	const sink = props.sink ?? nullBridgeTelemetrySink;
	const scheduleIdleFlush = props.scheduleIdleFlush ?? defaultIdleFlushScheduler;
	let idleFlushScheduled = false;
	let nextSequence = 0;
	const scheduleFlush = (flush: () => boolean): void => {
		if (idleFlushScheduled) {
			return;
		}
		idleFlushScheduled = true;
		scheduleIdleFlush((): void => {
			idleFlushScheduled = false;
			flush();
		});
	};
	const peekNextBatchSequence = (): number => nextSequence + 1;
	const commitBatchSequence = (sequence: number): void => {
		nextSequence = sequence;
	};
	const flushSnapshot = (): boolean => {
		const snapshot = buffer.drain();
		const samples = samplesWithDropCounters(snapshot.samples, snapshot.dropCounters);
		if (samples.length === 0) {
			return true;
		}
		const sequence = peekNextBatchSequence();
		const didFlush = sink.flush(makeBridgeTelemetryBatch(props.config.scenario, sequence, samples));
		if (!didFlush) {
			buffer.restore(snapshot);
			return false;
		}
		commitBatchSequence(sequence);
		return true;
	};
	const client: BridgeCommWorkerTelemetryClient = {
		isEnabled: (scope): boolean => props.config.enabledScopes.has(scope),
		record: (sample): void => {
			if (!props.config.enabledScopes.has(sample.scope)) {
				return;
			}
			buffer.add(sample);
			scheduleFlush(flushSnapshot);
		},
		flush: flushSnapshot,
		transport: {
			endpointUrl: props.config.endpointUrl,
		},
	};
	return client;
}

export function readBridgeCommWorkerAbsoluteNowMilliseconds(
	clock: BridgeCommWorkerPerformanceClock = performance,
): number {
	return clock.timeOrigin + clock.now();
}

export interface RecordBridgeCommWorkerTaskTelemetryProps {
	readonly action?: string;
	readonly command?: string;
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

type BridgeCommWorkerTelemetryResultReason = NonNullable<
	BridgeWorkerContentAvailabilityPatchPayload['reason']
>;

function bridgeCommWorkerTaskPriority(lane: BridgeCommWorkerTelemetryLane): string {
	return lane === 'selected' ? 'hot' : 'warm';
}

function samplesWithDropCounters(
	samples: readonly BridgeTelemetrySample[],
	dropCounters: readonly BridgeTelemetryDropCounter[],
): readonly BridgeTelemetrySample[] {
	if (dropCounters.length === 0) {
		return samples;
	}
	return [...samples, ...dropCounters.map(makeTelemetryDropSample)];
}

function makeTelemetryDropSample(counter: BridgeTelemetryDropCounter): BridgeTelemetrySample {
	return {
		scope: 'web',
		name: 'performance.bridge.web.telemetry_drop',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'dropped',
			'agentstudio.bridge.plane': 'observability',
			'agentstudio.bridge.priority': 'best_effort',
			'agentstudio.bridge.slice': 'telemetry_drop',
			'agentstudio.bridge.telemetry.drop_reason': counter.reason,
			'agentstudio.bridge.telemetry.event_name': counter.eventName,
			'agentstudio.bridge.telemetry.lane': counter.lane,
			'agentstudio.bridge.telemetry.result': counter.result,
			'agentstudio.bridge.transport': 'scheme',
		},
		numericAttributes: {
			'agentstudio.bridge.telemetry.dropped_count': counter.count,
		},
		booleanAttributes: {},
	};
}

function defaultIdleFlushScheduler(callback: () => void): void {
	const idleCallback = globalThis.requestIdleCallback;
	if (idleCallback === undefined) {
		globalThis.setTimeout(callback, 0);
		return;
	}
	idleCallback(callback, { timeout: 1_000 });
}
