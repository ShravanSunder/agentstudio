import { z } from 'zod';

import { bridgeProductReviewComparisonPresentationSchema } from './bridge-product-session-contracts.js';

export const bridgeWorkerPanelChromePatchPayloadSchema = z
	.object({
		isLoading: z.boolean().optional(),
		message: z.string().min(1).nullable().optional(),
		reviewComparison: bridgeProductReviewComparisonPresentationSchema.nullable().optional(),
	})
	.strict();

export const bridgeWorkerPanelChromePatchSchema = z.discriminatedUnion('operation', [
	z
		.object({
			slice: z.literal('panelChrome'),
			operation: z.literal('upsert'),
			payload: bridgeWorkerPanelChromePatchPayloadSchema,
		})
		.strict(),
	z
		.object({
			slice: z.literal('panelChrome'),
			operation: z.literal('reset'),
		})
		.strict(),
	z
		.object({
			slice: z.literal('panelChrome'),
			operation: z.literal('delete'),
		})
		.strict(),
]);

export type BridgeWorkerPanelChromePatchPayload = z.infer<
	typeof bridgeWorkerPanelChromePatchPayloadSchema
>;
