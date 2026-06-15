import { z } from 'zod';

import { type BridgeTelemetryScope, bridgeTelemetryScopeSchema } from './bridge-telemetry-scope.js';

export interface BridgeTelemetryBootstrapConfig {
	readonly enabledScopes: ReadonlySet<BridgeTelemetryScope>;
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
});

export function decodeBridgeTelemetryBootstrapConfig(
	value: unknown,
): BridgeTelemetryBootstrapConfig | null {
	const result = bridgeTelemetryBootstrapConfigSchema.safeParse(value);
	if (!result.success || result.data.enabledScopes.length === 0) {
		return null;
	}
	return {
		...result.data,
		enabledScopes: new Set(result.data.enabledScopes),
	};
}
