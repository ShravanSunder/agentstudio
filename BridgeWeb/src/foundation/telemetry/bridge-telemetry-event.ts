import { z } from 'zod';

import { bridgeTelemetryScopeSchema } from './bridge-telemetry-scope.js';
import type { BridgeTraceContext } from './bridge-trace-context.js';
import { decodeBridgeTraceContext } from './bridge-trace-context.js';

export interface BridgeTelemetrySample {
	readonly scope: z.infer<typeof bridgeTelemetryScopeSchema>;
	readonly name: string;
	readonly durationMilliseconds: number | null;
	readonly traceContext: BridgeTraceContext | null;
	readonly stringAttributes: Readonly<Record<string, string>>;
	readonly numericAttributes: Readonly<Record<string, number>>;
	readonly booleanAttributes: Readonly<Record<string, boolean>>;
}

export interface BridgeTelemetryBatch {
	readonly schemaVersion: 1;
	readonly scenario: string;
	readonly samples: readonly BridgeTelemetrySample[];
}

export function makeBridgeTelemetryBatch(
	scenario: string,
	samples: readonly BridgeTelemetrySample[],
): BridgeTelemetryBatch {
	return {
		schemaVersion: 1,
		scenario,
		samples,
	};
}

export function makeBridgeTelemetrySample(props: BridgeTelemetrySample): BridgeTelemetrySample {
	return {
		scope: props.scope,
		name: props.name,
		durationMilliseconds: props.durationMilliseconds,
		traceContext: props.traceContext === null ? null : decodeBridgeTraceContext(props.traceContext),
		stringAttributes: props.stringAttributes,
		numericAttributes: props.numericAttributes,
		booleanAttributes: props.booleanAttributes,
	};
}
