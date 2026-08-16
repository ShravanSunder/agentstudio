import { z } from 'zod';

import {
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_STREAM_BYTES,
	bridgeProductIdentifierSchema,
	bridgeProductPositiveSequenceSchema,
	bridgeProductSha256Schema,
} from './bridge-product-contract-primitives.js';
import { bridgeProductReviewPublicationIdSchema } from './bridge-product-review-primitives.js';

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
