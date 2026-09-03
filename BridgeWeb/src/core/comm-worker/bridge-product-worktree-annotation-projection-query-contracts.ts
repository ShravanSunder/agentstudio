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
export const BRIDGE_PRODUCT_MAXIMUM_ANNOTATION_PROJECTION_PAGE_COUNT = 128;
export const BRIDGE_PRODUCT_MAXIMUM_ANNOTATION_PROJECTION_PAGE_BYTES =
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES;

export const bridgeProductReviewAnnotationPublicationIdentitySchema = z
	.object({
		packageId: bridgeProductIdentifierSchema,
		publicationId: bridgeProductReviewPublicationIdSchema,
		reviewGeneration: bridgeProductNonnegativeSequenceSchema,
		revision: bridgeProductNonnegativeSequenceSchema,
		sourceIdentity: bridgeProductIdentifierSchema,
	})
	.strict();

export const bridgeProductAnnotationProjectionQueryRequestSchema = z
	.object({
		cursor: bridgeProductOpaqueReferenceSchema.nullable(),
		operationCorrelationId: bridgeProductSha256Schema,
		sessionIds: z
			.array(bridgeProductReviewPublicationIdSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_ANNOTATION_PROJECTION_SESSION_COUNT)
			.refine((sessionIds) => new Set(sessionIds).size === sessionIds.length, {
				message: 'Demanded annotation sessions must be unique.',
			}),
		reviewPublicationIdentity: bridgeProductReviewAnnotationPublicationIdentitySchema.optional(),
		sourceGeneration: bridgeProductNonnegativeSequenceSchema,
		surface: bridgeProductSurfaceSchema,
	})
	.strict()
	.superRefine((request, context): void => {
		if (request.surface === 'review' && request.reviewPublicationIdentity === undefined) {
			context.addIssue({
				code: 'custom',
				message: 'Review annotation projection requires installed publication identity.',
				path: ['reviewPublicationIdentity'],
			});
		}
		if (request.surface === 'file' && request.reviewPublicationIdentity !== undefined) {
			context.addIssue({
				code: 'custom',
				message: 'File annotation projection cannot carry Review publication identity.',
				path: ['reviewPublicationIdentity'],
			});
		}
		if (
			request.reviewPublicationIdentity !== undefined &&
			request.reviewPublicationIdentity.reviewGeneration !== request.sourceGeneration
		) {
			context.addIssue({
				code: 'custom',
				message:
					'Review annotation projection generation must match installed publication identity.',
				path: ['sourceGeneration'],
			});
		}
	});

export const bridgeProductAnnotationProjectionPageContractSchema = z
	.object({
		aggregateSha256: bridgeProductSha256Schema,
		expectedMessageCount: bridgeProductNonnegativeSequenceSchema,
		expectedPageCount: z
			.number()
			.int()
			.positive()
			.max(BRIDGE_PRODUCT_MAXIMUM_ANNOTATION_PROJECTION_PAGE_COUNT),
		expectedSessionCount: bridgeProductNonnegativeSequenceSchema,
		expectedThreadCount: bridgeProductNonnegativeSequenceSchema,
		isLastPage: z.boolean(),
		nextCursor: bridgeProductOpaqueReferenceSchema.nullable(),
		operationCorrelationId: bridgeProductSha256Schema,
		pageOrdinal: bridgeProductNonnegativeSequenceSchema,
		projectionRevision: bridgeProductNonnegativeSequenceSchema,
		snapshotId: bridgeProductReviewPublicationIdSchema,
		sourceGeneration: bridgeProductNonnegativeSequenceSchema,
	})
	.strict()
	.refine((page) => page.isLastPage === (page.nextCursor === null), {
		message: 'Annotation projection continuation must agree with isLastPage.',
		path: ['nextCursor'],
	})
	.refine((page) => page.isLastPage === (page.pageOrdinal + 1 === page.expectedPageCount), {
		message: 'Annotation projection final page must agree with expectedPageCount.',
		path: ['expectedPageCount'],
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

export const bridgeProductAnnotationProjectionQueryResultSchema = z.discriminatedUnion('kind', [
	z
		.object({
			descriptor: bridgeProductAnnotationProjectionContentDescriptorSchema,
			kind: z.literal('content'),
		})
		.strict(),
	z
		.object({
			currentSourceGeneration: bridgeProductNonnegativeSequenceSchema,
			kind: z.literal('source_stale'),
		})
		.strict(),
]);

export type BridgeProductAnnotationProjectionQueryRequest = z.infer<
	typeof bridgeProductAnnotationProjectionQueryRequestSchema
>;
export type BridgeProductReviewAnnotationPublicationIdentity = z.infer<
	typeof bridgeProductReviewAnnotationPublicationIdentitySchema
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
export type BridgeProductAnnotationProjectionQueryResult = z.infer<
	typeof bridgeProductAnnotationProjectionQueryResultSchema
>;
