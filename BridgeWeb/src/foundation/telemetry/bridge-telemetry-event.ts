import { z } from 'zod';

import { bridgeTelemetryScopeSchema } from './bridge-telemetry-scope.js';
import type { BridgeTraceContext } from './bridge-trace-context.js';
import { decodeBridgeTraceContext } from './bridge-trace-context.js';

export const bridgeTelemetrySampleSchema = z.object({
	scope: bridgeTelemetryScopeSchema,
	name: z.string().min(1),
	durationMilliseconds: z.number().nonnegative().nullable(),
	traceContext: z.custom<BridgeTraceContext | null>(
		(value): boolean => value === null || decodeBridgeTraceContext(value) !== null,
	),
	stringAttributes: z.record(z.string(), z.string()),
	numericAttributes: z.record(z.string(), z.number()),
	booleanAttributes: z.record(z.string(), z.boolean()),
});

export type BridgeTelemetrySample = z.infer<typeof bridgeTelemetrySampleSchema>;

export const bridgeTelemetryBatchSchema = z.object({
	schemaVersion: z.literal(1),
	scenario: z.string().min(1),
	samples: z.array(bridgeTelemetrySampleSchema).readonly(),
});

export type BridgeTelemetryBatch = z.infer<typeof bridgeTelemetryBatchSchema>;

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
