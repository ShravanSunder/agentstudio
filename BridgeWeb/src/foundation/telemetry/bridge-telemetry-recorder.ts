import type { BridgeTelemetryBootstrapConfig } from './bridge-telemetry-bootstrap-config.js';
import {
	createBridgeTelemetryBuffer,
	type BridgeTelemetryBuffer,
	type BridgeTelemetryDropCounter,
} from './bridge-telemetry-buffer.js';
import { makeBridgeTelemetryBatch, type BridgeTelemetrySample } from './bridge-telemetry-event.js';
import type { BridgeTelemetryScope } from './bridge-telemetry-scope.js';
import { nullBridgeTelemetrySink, type BridgeTelemetrySink } from './bridge-telemetry-sink.js';
import type { BridgeTraceContext } from './bridge-trace-context.js';

export interface BridgeTelemetryRecorder {
	readonly isEnabled: (scope: BridgeTelemetryScope) => boolean;
	readonly record: (sample: BridgeTelemetrySample) => void;
	readonly measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>) => TResult;
	readonly flush: (props?: BridgeTelemetryFlushProps) => boolean;
}

export interface BridgeTelemetryRecorderClient {
	readonly record: (sample: BridgeTelemetrySample) => void;
	readonly flush: () => boolean;
}

export interface BridgeTelemetryMeasureProps<TResult> {
	readonly scope: BridgeTelemetryScope;
	readonly name: string;
	readonly traceContext: BridgeTraceContext | null;
	readonly stringAttributes: Readonly<Record<string, string>>;
	readonly numericAttributes?: Readonly<Record<string, number>>;
	readonly booleanAttributes?: Readonly<Record<string, boolean>>;
	readonly operation: () => TResult;
}

export interface BridgeTelemetryFlushProps {
	readonly force?: boolean;
}

type BridgeTelemetryIdleFlushScheduler = (callback: () => void) => void;

export function createBridgeTelemetryRecorder(
	config: BridgeTelemetryBootstrapConfig | null,
	sink: BridgeTelemetrySink = nullBridgeTelemetrySink,
	now: () => number = performance.now.bind(performance),
	scheduleIdleFlush: BridgeTelemetryIdleFlushScheduler = defaultIdleFlushScheduler,
): BridgeTelemetryRecorder {
	if (config === null) {
		return nullBridgeTelemetryRecorder;
	}
	const buffer = createBridgeTelemetryBuffer({
		maxSamplesPerBatch: config.maxSamplesPerBatch,
		maxEncodedBatchBytes: config.maxEncodedBatchBytes,
	});
	return createEnabledBridgeTelemetryRecorder(config, buffer, sink, now, scheduleIdleFlush);
}

export function createBridgeTelemetryRecorderFromClient(
	config: BridgeTelemetryBootstrapConfig | null,
	client: BridgeTelemetryRecorderClient,
	now: () => number = performance.now.bind(performance),
): BridgeTelemetryRecorder {
	if (config === null) {
		return nullBridgeTelemetryRecorder;
	}
	return {
		isEnabled: (scope): boolean => config.enabledScopes.has(scope),
		record: (sample): void => {
			if (config.enabledScopes.has(sample.scope)) {
				client.record(sample);
			}
		},
		measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => {
			if (!config.enabledScopes.has(props.scope)) {
				return props.operation();
			}
			const start = now();
			const result = props.operation();
			client.record({
				scope: props.scope,
				name: props.name,
				durationMilliseconds: Math.max(0, now() - start),
				traceContext: props.traceContext,
				stringAttributes: props.stringAttributes,
				numericAttributes: props.numericAttributes ?? {},
				booleanAttributes: props.booleanAttributes ?? {},
			});
			return result;
		},
		flush: (): boolean => client.flush(),
	};
}

const nullBridgeTelemetryRecorder: BridgeTelemetryRecorder = {
	isEnabled: (): boolean => false,
	record: (): void => {},
	measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => props.operation(),
	flush: (): boolean => true,
};

function createEnabledBridgeTelemetryRecorder(
	config: BridgeTelemetryBootstrapConfig,
	buffer: BridgeTelemetryBuffer,
	sink: BridgeTelemetrySink,
	now: () => number,
	scheduleIdleFlush: BridgeTelemetryIdleFlushScheduler,
): BridgeTelemetryRecorder {
	let lastFlushAtMilliseconds: number | null = null;
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
	const recorder: BridgeTelemetryRecorder = {
		isEnabled: (scope: BridgeTelemetryScope): boolean => config.enabledScopes.has(scope),
		record: (sample: BridgeTelemetrySample): void => {
			if (config.enabledScopes.has(sample.scope)) {
				buffer.add(sample);
				scheduleFlush((): boolean => recorder.flush());
			}
		},
		measure: <TResult>(props: BridgeTelemetryMeasureProps<TResult>): TResult => {
			if (!config.enabledScopes.has(props.scope)) {
				return props.operation();
			}
			const start = now();
			const result = props.operation();
			buffer.add({
				scope: props.scope,
				name: props.name,
				durationMilliseconds: Math.max(0, now() - start),
				traceContext: props.traceContext,
				stringAttributes: props.stringAttributes,
				numericAttributes: props.numericAttributes ?? {},
				booleanAttributes: props.booleanAttributes ?? {},
			});
			scheduleFlush((): boolean => recorder.flush());
			return result;
		},
		flush: (props: BridgeTelemetryFlushProps = {}): boolean => {
			const currentTimeMilliseconds = now();
			if (!props.force && !canFlushAt(config, lastFlushAtMilliseconds, currentTimeMilliseconds)) {
				return true;
			}
			const snapshot = buffer.drain();
			const dropSamples = snapshot.dropCounters.map(makeTelemetryDropSample);
			if (snapshot.shedRequiredEventCount > 0) {
				dropSamples.push(makeRequiredEventShedTelemetryDropSample(snapshot.shedRequiredEventCount));
			}
			const samples =
				dropSamples.length === 0 ? snapshot.samples : [...snapshot.samples, ...dropSamples];
			if (samples.length === 0) {
				return true;
			}
			const sequence = peekNextBatchSequence();
			const didFlush = sink.flush(makeBridgeTelemetryBatch(config.scenario, sequence, samples));
			if (!didFlush) {
				buffer.restore(snapshot);
				return false;
			}
			commitBatchSequence(sequence);
			lastFlushAtMilliseconds = currentTimeMilliseconds;
			return true;
		},
	};
	return recorder;
}

function canFlushAt(
	config: BridgeTelemetryBootstrapConfig,
	lastFlushAtMilliseconds: number | null,
	currentTimeMilliseconds: number,
): boolean {
	return (
		lastFlushAtMilliseconds === null ||
		currentTimeMilliseconds - lastFlushAtMilliseconds >= config.minimumFlushIntervalMilliseconds
	);
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

function makeRequiredEventShedTelemetryDropSample(
	shedRequiredEventCount: number,
): BridgeTelemetrySample {
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
			'agentstudio.bridge.telemetry.drop_reason': 'required_event_shed',
			'agentstudio.bridge.transport': 'scheme',
		},
		numericAttributes: {
			'agentstudio.bridge.telemetry.dropped_count': shedRequiredEventCount,
			'agentstudio.bridge.telemetry.required_dropped_count': shedRequiredEventCount,
		},
		booleanAttributes: {},
	};
}

function defaultIdleFlushScheduler(callback: () => void): void {
	const idleCallback = globalThis.requestIdleCallback;
	if (idleCallback === undefined) {
		return;
	}
	idleCallback(callback, { timeout: 1_000 });
}
