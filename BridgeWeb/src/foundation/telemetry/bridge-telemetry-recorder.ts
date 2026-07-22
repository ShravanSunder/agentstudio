import type { BridgeTelemetryBootstrapConfig } from './bridge-telemetry-bootstrap-config.js';
import type { BridgeTelemetrySample } from './bridge-telemetry-event.js';
import type { BridgeTelemetryScope } from './bridge-telemetry-scope.js';
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

export function createBridgeTelemetryRecorder(_config: null): BridgeTelemetryRecorder {
	return nullBridgeTelemetryRecorder;
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
