import { z } from 'zod';

const bridgeWorkerFileQuerySearchTextMaximumLength = 4_096;

export const bridgeWorkerFileQuerySchema = z
	.object({
		filterMode: z.enum(['all', 'fetchable', 'unavailable']),
		searchMode: z.enum(['text', 'regex']),
		searchText: z.string().max(bridgeWorkerFileQuerySearchTextMaximumLength),
	})
	.strict();

export type BridgeWorkerFileQuery = z.infer<typeof bridgeWorkerFileQuerySchema>;

export const bridgeWorkerFileQueryDisplayPayloadSchema = bridgeWorkerFileQuerySchema
	.extend({
		projectedRowCount: z.number().int().nonnegative(),
		searchError: z.string().min(1).nullable(),
		totalRowCount: z.number().int().nonnegative(),
	})
	.strict();

export type BridgeWorkerFileQueryDisplayPayload = z.infer<
	typeof bridgeWorkerFileQueryDisplayPayloadSchema
>;
