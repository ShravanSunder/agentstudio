import { z } from 'zod';

import { type BridgeTelemetryScope, bridgeTelemetryScopeSchema } from './bridge-telemetry-scope.js';

export interface BridgeTelemetryBootstrapConfig {
	readonly enabledScopes: ReadonlySet<BridgeTelemetryScope>;
	readonly maxSamplesPerBatch: number;
	readonly maxEncodedBatchBytes: number;
	readonly minimumFlushIntervalMilliseconds: number;
	readonly rpcMethodName: 'system.bridgeTelemetry';
	readonly scenario: string;
	// Native wall-clock epoch (Unix milliseconds) when the viewer open began. Used as the
	// cold `time_to_first_interaction` start anchor; absent when telemetry is disabled.
	readonly viewerOpenEpochUnixMillis?: number;
	// W3C traceparent for the native viewer-open root span, joining the browser
	// first-interaction sample to the native trace.
	readonly viewerOpenTraceparent?: string;
}

export interface BridgeTelemetryBootstrapHandshakeConfig {
	readonly enabledScopes: readonly BridgeTelemetryScope[];
	readonly maxSamplesPerBatch: number;
	readonly maxEncodedBatchBytes: number;
	readonly minimumFlushIntervalMilliseconds: number;
	readonly rpcMethodName: 'system.bridgeTelemetry';
	readonly scenario: string;
}

const bridgeTelemetryBootstrapConfigSchema = z.object({
	enabledScopes: z.array(bridgeTelemetryScopeSchema),
	maxSamplesPerBatch: z.number().int().positive(),
	maxEncodedBatchBytes: z.number().int().positive(),
	minimumFlushIntervalMilliseconds: z.number().int().nonnegative(),
	rpcMethodName: z.literal('system.bridgeTelemetry'),
	scenario: z.string().min(1),
	viewerOpenEpochUnixMillis: z.number().int().positive().optional(),
	viewerOpenTraceparent: z.string().min(1).optional(),
});

export function decodeBridgeTelemetryBootstrapConfig(
	value: unknown,
): BridgeTelemetryBootstrapConfig | null {
	const result = bridgeTelemetryBootstrapConfigSchema.safeParse(value);
	if (!result.success || result.data.enabledScopes.length === 0) {
		return null;
	}
	const { viewerOpenEpochUnixMillis, viewerOpenTraceparent, ...rest } = result.data;
	return {
		...rest,
		enabledScopes: new Set(result.data.enabledScopes),
		...(viewerOpenEpochUnixMillis === undefined ? {} : { viewerOpenEpochUnixMillis }),
		...(viewerOpenTraceparent === undefined ? {} : { viewerOpenTraceparent }),
	};
}
