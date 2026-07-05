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

type BridgeCommWorkerTelemetryIdleFlushScheduler = (callback: () => void) => void;

export interface BridgeCommWorkerTelemetryTransport {
	readonly endpointUrl: string;
}

export interface BridgeCommWorkerTelemetryClient {
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
	const nextBatchSequence = (): number => {
		nextSequence += 1;
		return nextSequence;
	};
	const flushSnapshot = (): boolean => {
		const snapshot = buffer.drain();
		const samples = samplesWithDropCounters(snapshot.samples, snapshot.dropCounters);
		if (samples.length === 0) {
			return true;
		}
		const didFlush = sink.flush(
			makeBridgeTelemetryBatch(props.config.scenario, nextBatchSequence(), samples),
		);
		if (!didFlush) {
			buffer.restore(snapshot);
			return false;
		}
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
