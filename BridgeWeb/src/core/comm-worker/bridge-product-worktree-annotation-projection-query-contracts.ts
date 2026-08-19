import { z } from 'zod';

import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductOpaqueReferenceSchema,
	bridgeProductSha256Schema,
	bridgeProductSurfaceSchema,
} from './bridge-product-contract-primitives.js';
import { bridgeProductReviewPublicationIdSchema } from './bridge-product-review-primitives.js';

export const BRIDGE_PRODUCT_MAXIMUM_ANNOTATION_PROJECTION_SESSION_COUNT = 128;
export const BRIDGE_PRODUCT_MAXIMUM_ANNOTATION_PROJECTION_PAGE_BYTES =
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES;

export const bridgeProductAnnotationProjectionQueryRequestSchema = z
	.object({
		cursor: bridgeProductOpaqueReferenceSchema.nullable(),
		sessionIds: z
			.array(bridgeProductReviewPublicationIdSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_ANNOTATION_PROJECTION_SESSION_COUNT)
			.refine((sessionIds) => new Set(sessionIds).size === sessionIds.length, {
				message: 'Demanded annotation sessions must be unique.',
			}),
		sourceGeneration: bridgeProductNonnegativeSequenceSchema,
		surface: bridgeProductSurfaceSchema,
	})
	.strict();

export const bridgeProductAnnotationProjectionPageContractSchema = z
	.object({
		aggregateSha256: bridgeProductSha256Schema,
		expectedMessageCount: bridgeProductNonnegativeSequenceSchema,
		expectedSessionCount: bridgeProductNonnegativeSequenceSchema,
		expectedThreadCount: bridgeProductNonnegativeSequenceSchema,
		isLastPage: z.boolean(),
		nextCursor: bridgeProductOpaqueReferenceSchema.nullable(),
		pageOrdinal: bridgeProductNonnegativeSequenceSchema,
		projectionRevision: bridgeProductNonnegativeSequenceSchema,
		snapshotId: bridgeProductReviewPublicationIdSchema,
		sourceGeneration: bridgeProductNonnegativeSequenceSchema,
	})
	.strict()
	.refine((page) => page.isLastPage === (page.nextCursor === null), {
		message: 'Annotation projection continuation must agree with isLastPage.',
		path: ['nextCursor'],
	});

export const bridgeProductAnnotationProjectionContentDescriptorSchema = z
	.object({
		contentKind: z.literal('annotation.projection'),
		descriptorId: bridgeProductIdentifierSchema,
		maximumBytes: z
			.number()
			.int()
			.positive()
			.max(BRIDGE_PRODUCT_MAXIMUM_ANNOTATION_PROJECTION_PAGE_BYTES),
		page: bridgeProductAnnotationProjectionPageContractSchema,
		surface: bridgeProductSurfaceSchema,
	})
	.strict();

export const bridgeProductAnnotationProjectionContentIdentitySchema =
	bridgeProductAnnotationProjectionContentDescriptorSchema;

export const bridgeProductAnnotationProjectionQueryResultSchema = z
	.object({ descriptor: bridgeProductAnnotationProjectionContentDescriptorSchema })
	.strict();

export type BridgeProductAnnotationProjectionQueryRequest = z.infer<
	typeof bridgeProductAnnotationProjectionQueryRequestSchema
>;
export type BridgeProductAnnotationProjectionPageContract = z.infer<
	typeof bridgeProductAnnotationProjectionPageContractSchema
>;
export type BridgeProductAnnotationProjectionContentDescriptor = z.infer<
	typeof bridgeProductAnnotationProjectionContentDescriptorSchema
>;
export type BridgeProductAnnotationProjectionContentIdentity = z.infer<
	typeof bridgeProductAnnotationProjectionContentIdentitySchema
>;
