import { z } from 'zod';

import { bridgeProductReviewComparisonTargetCatalogSchema } from './bridge-product-review-comparison-contracts.js';

const bridgeWorkerWireVersionSchema = z.literal(1);
const bridgeWorkerTransferDescriptorSchema = z
	.object({
		messageKind: z.string().min(1),
		fieldPath: z.array(z.string().min(1)).readonly(),
		byteLength: z.number().int().nonnegative(),
		mode: z.enum(['transfer', 'clone']),
	})
	.strict();
const bridgeWorkerRequestIdSchema = z.string().min(1);
const bridgeWorkerMainToServerBaseSchema = z
	.object({
		wireVersion: bridgeWorkerWireVersionSchema,
		direction: z.literal('mainToServerWorker'),
		kind: z.literal('command'),
		requestId: bridgeWorkerRequestIdSchema,
		epoch: z.number().int().nonnegative(),
		issuedAtMilliseconds: z.number().finite().nonnegative().optional(),
		transferDescriptors: z.array(bridgeWorkerTransferDescriptorSchema).readonly(),
	})
	.strict();
const bridgeWorkerServerToMainBaseSchema = z
	.object({
		wireVersion: bridgeWorkerWireVersionSchema,
		direction: z.literal('serverWorkerToMain'),
		transferDescriptors: z.array(bridgeWorkerTransferDescriptorSchema).readonly(),
	})
	.strict();

export const bridgeWorkerReviewComparisonTargetsQueryCommandSchema =
	bridgeWorkerMainToServerBaseSchema
		.extend({ command: z.literal('reviewComparisonTargetsQuery') })
		.strict();

export const bridgeWorkerReviewComparisonTargetsQueryEventSchema =
	bridgeWorkerServerToMainBaseSchema
		.extend({
			catalog: bridgeProductReviewComparisonTargetCatalogSchema.nullable(),
			kind: z.literal('reviewComparisonTargetsQuery'),
			message: z.string().min(1).optional(),
			requestId: bridgeWorkerRequestIdSchema,
			status: z.enum(['empty', 'ready', 'failed']),
		})
		.strict()
		.superRefine((event, context): void => {
			if ((event.status === 'ready' || event.status === 'empty') && event.catalog === null) {
				context.addIssue({
					code: 'custom',
					message: 'A successful comparison-target query must include a catalog.',
					path: ['catalog'],
				});
			}
			if (event.status === 'empty' && event.catalog !== null && event.catalog.branches.length > 0) {
				context.addIssue({
					code: 'custom',
					message: 'An empty comparison-target query cannot include branch rows.',
					path: ['catalog', 'branches'],
				});
			}
			if (event.status === 'failed' && event.catalog !== null) {
				context.addIssue({
					code: 'custom',
					message: 'A failed comparison-target query cannot include a catalog.',
					path: ['catalog'],
				});
			}
			if (event.status === 'failed' && event.message === undefined) {
				context.addIssue({
					code: 'custom',
					message: 'A failed comparison-target query must include a safe message.',
					path: ['message'],
				});
			}
		});

export type BridgeWorkerReviewComparisonTargetsQueryCommand = z.infer<
	typeof bridgeWorkerReviewComparisonTargetsQueryCommandSchema
>;
export type BridgeWorkerReviewComparisonTargetsQueryEvent = z.infer<
	typeof bridgeWorkerReviewComparisonTargetsQueryEventSchema
>;
