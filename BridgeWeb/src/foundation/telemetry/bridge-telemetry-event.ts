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

export const bridgeTelemetryStreamIdSchema = z.enum(['page', 'comm-worker']);
export type BridgeTelemetryStreamId = z.infer<typeof bridgeTelemetryStreamIdSchema>;

export const bridgeTelemetryBatchSchema = z.object({
	schemaVersion: z.literal(1),
	scenario: z.string().min(1),
	streamId: bridgeTelemetryStreamIdSchema,
	sequence: z.number().int().positive().optional(),
	samples: z.array(bridgeTelemetrySampleSchema).readonly(),
});

export type BridgeTelemetryBatch = z.infer<typeof bridgeTelemetryBatchSchema>;

export interface MakeBridgeTelemetryBatchProps {
	readonly samples: readonly BridgeTelemetrySample[];
	readonly scenario: string;
	readonly sequence: number;
	readonly streamId: BridgeTelemetryStreamId;
}

export function makeBridgeTelemetryBatch(
	props: MakeBridgeTelemetryBatchProps,
): BridgeTelemetryBatch {
	return {
		schemaVersion: 1,
		scenario: props.scenario,
		streamId: props.streamId,
		sequence: props.sequence,
		samples: props.samples,
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
