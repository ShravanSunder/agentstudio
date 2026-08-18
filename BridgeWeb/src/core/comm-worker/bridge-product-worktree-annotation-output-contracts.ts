import { z } from 'zod';

import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES,
	bridgeProductDisplayPathSchema,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductPositiveSequenceSchema,
	bridgeProductSha256Schema,
} from './bridge-product-contract-primitives.js';
import { bridgeProductReviewPublicationIdSchema } from './bridge-product-review-primitives.js';

export const bridgeProductWorktreeAnnotationOutputCandidateCursorSchema = z
	.object({
		flatOrdinal: bridgeProductNonnegativeSequenceSchema,
		kind: z.literal('after'),
		messageId: bridgeProductReviewPublicationIdSchema,
	})
	.strict();

export const bridgeProductWorktreeAnnotationOutputCandidateSchema = z
	.object({
		authoredAt: z.number().finite(),
		endLine: bridgeProductNonnegativeSequenceSchema.positive(),
		excerpt: z.string().max(512),
		flatOrdinal: bridgeProductNonnegativeSequenceSchema,
		location: z.enum(['current', 'original']),
		messageId: bridgeProductReviewPublicationIdSchema,
		path: bridgeProductDisplayPathSchema,
		placement: z.enum(['exact', 'relocated', 'outdated', 'unavailable']),
		state: z.literal('eligible'),
		startLine: bridgeProductNonnegativeSequenceSchema.positive(),
		threadId: bridgeProductReviewPublicationIdSchema,
	})
	.strict()
	.refine((candidate) => candidate.endLine >= candidate.startLine, {
		message: 'Annotation output candidate endLine cannot precede startLine.',
		path: ['endLine'],
	});

export const bridgeProductWorktreeAnnotationOutputCandidatePageSchema = z
	.object({
		candidates: z.array(bridgeProductWorktreeAnnotationOutputCandidateSchema).max(16).readonly(),
		eligibleMessageCount: bridgeProductNonnegativeSequenceSchema,
		eligibleWithoutInlinePlacementCount: bridgeProductNonnegativeSequenceSchema,
		nextCursor: bridgeProductWorktreeAnnotationOutputCandidateCursorSchema.nullable(),
		sessionId: bridgeProductReviewPublicationIdSchema,
		sessionRevision: bridgeProductNonnegativeSequenceSchema,
	})
	.strict();

export const bridgeProductWorktreeAnnotationOutputCandidateQueryRequestSchema = z
	.object({
		cursor: z.discriminatedUnion('kind', [
			z.object({ kind: z.literal('start') }).strict(),
			bridgeProductWorktreeAnnotationOutputCandidateCursorSchema,
		]),
		expectedSessionRevision: bridgeProductNonnegativeSequenceSchema,
		limit: z.number().int().min(1).max(16),
		sessionId: bridgeProductReviewPublicationIdSchema,
	})
	.strict();

const bridgeProductAnnotationOutputDescriptorBaseShape = {
	attemptId: bridgeProductReviewPublicationIdSchema,
	contentKind: z.literal('annotation.output'),
	declaredByteLength: bridgeProductPositiveSequenceSchema.max(
		BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES,
	),
	descriptorId: bridgeProductIdentifierSchema,
	encoding: z.literal('utf-8'),
	expectedSha256: bridgeProductSha256Schema,
	formatVersion: z.literal(1),
	maximumBytes: bridgeProductPositiveSequenceSchema.max(
		BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES,
	),
	surface: z.enum(['file', 'review']),
} as const;

export const bridgeProductAnnotationOutputContentDescriptorSchema = z
	.discriminatedUnion('outputKind', [
		z
			.object({
				...bridgeProductAnnotationOutputDescriptorBaseShape,
				contentType: z.literal('text/markdown; charset=utf-8'),
				outputKind: z.literal('clipboard_markdown'),
			})
			.strict(),
		z
			.object({
				...bridgeProductAnnotationOutputDescriptorBaseShape,
				contentType: z.literal('application/json; charset=utf-8'),
				outputKind: z.literal('json_file'),
			})
			.strict(),
	])
	.refine((descriptor) => descriptor.declaredByteLength === descriptor.maximumBytes, {
		message: 'Annotation output maximum must equal its declared length.',
		path: ['maximumBytes'],
	});

export const bridgeProductAnnotationOutputContentIdentitySchema = z
	.object({
		attemptId: bridgeProductReviewPublicationIdSchema,
		contentKind: z.literal('annotation.output'),
		descriptorId: bridgeProductIdentifierSchema,
		formatVersion: z.literal(1),
		maximumBytes: bridgeProductPositiveSequenceSchema.max(
			BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES,
		),
		outputKind: z.enum(['clipboard_markdown', 'json_file']),
		surface: z.enum(['file', 'review']),
	})
	.strict();

export const bridgeProductWorktreeAnnotationOutputInspectRequestSchema = z
	.object({ attemptId: bridgeProductReviewPublicationIdSchema })
	.strict();

export const bridgeProductWorktreeAnnotationOutputInspectResultSchema = z
	.object({ descriptor: bridgeProductAnnotationOutputContentDescriptorSchema })
	.strict();

export type BridgeProductAnnotationOutputContentDescriptor = z.infer<
	typeof bridgeProductAnnotationOutputContentDescriptorSchema
>;
export type BridgeProductAnnotationOutputContentIdentity = z.infer<
	typeof bridgeProductAnnotationOutputContentIdentitySchema
>;
