import type { BridgeTelemetryBootstrapConfig } from './bridge-telemetry-bootstrap-config.js';
import {
	createBridgeTelemetryBuffer,
	type BridgeTelemetryBuffer,
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

export function createBridgeTelemetryRecorder(
	config: BridgeTelemetryBootstrapConfig | null,
	sink: BridgeTelemetrySink = nullBridgeTelemetrySink,
	now: () => number = performance.now.bind(performance),
): BridgeTelemetryRecorder {
	if (config === null) {
		return nullBridgeTelemetryRecorder;
	}
	const buffer = createBridgeTelemetryBuffer(config.maxSamplesPerBatch);
	return createEnabledBridgeTelemetryRecorder(config, buffer, sink, now);
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
): BridgeTelemetryRecorder {
	let lastFlushAtMilliseconds: number | null = null;
	return {
		isEnabled: (scope: BridgeTelemetryScope): boolean => config.enabledScopes.has(scope),
		record: (sample: BridgeTelemetrySample): void => {
			if (config.enabledScopes.has(sample.scope)) {
				buffer.add(sample);
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
			return result;
		},
		flush: (props: BridgeTelemetryFlushProps = {}): boolean => {
			const currentTimeMilliseconds = now();
			if (!props.force && !canFlushAt(config, lastFlushAtMilliseconds, currentTimeMilliseconds)) {
				return true;
			}
			const snapshot = buffer.drain();
			const samples =
				snapshot.droppedCount === 0
					? snapshot.samples
					: [...snapshot.samples, makeTelemetryDropSample(snapshot.droppedCount)];
			if (samples.length === 0) {
				return true;
			}
			const didFlush = sink.flush(makeBridgeTelemetryBatch(config.scenario, samples));
			if (!didFlush) {
				buffer.restore(snapshot);
				return false;
			}
			lastFlushAtMilliseconds = currentTimeMilliseconds;
			return true;
		},
	};
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

function makeTelemetryDropSample(droppedCount: number): BridgeTelemetrySample {
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
			'agentstudio.bridge.telemetry.drop_reason': 'queue_saturated',
			'agentstudio.bridge.transport': 'rpc',
		},
		numericAttributes: {
			'agentstudio.bridge.telemetry.dropped_count': droppedCount,
		},
		booleanAttributes: {},
	};
}
