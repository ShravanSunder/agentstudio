import { z } from 'zod';

import { bridgeProductReviewContentDescriptorSchema } from './bridge-product-content-contracts.js';
import {
	bridgeProductReviewContentLineCountsByRoleSchema,
	bridgeProductReviewContentRoleSchema,
	bridgeProductReviewFileChangeKindSchema,
} from './bridge-product-review-primitives.js';
import {
	bridgeProductFileTruncationKindSchema,
	bridgeProductFileVirtualizedExtentKindSchema,
} from './bridge-product-subscription-contracts.js';

const bridgeWorkerSelectionSourceSchema = z.enum(['user', 'keyboard', 'programmatic']);

export const bridgeWorkerSelectionPatchPayloadSchema = z
	.object({
		selectedItemId: z.string().min(1),
		source: bridgeWorkerSelectionSourceSchema.nullable().optional(),
	})
	.strict();
export const bridgeWorkerViewportPatchPayloadSchema = z
	.object({
		firstVisibleIndex: z.number().int().nonnegative(),
		lastVisibleIndex: z.number().int().nonnegative(),
		visibleItemIds: z.array(z.string().min(1)).readonly(),
	})
	.strict();
export const bridgeWorkerRowPaintPatchPayloadSchema = z
	.object({
		contentCacheKey: z.string().min(1).optional(),
		label: z.string().min(1).optional(),
		status: z.string().min(1).optional(),
	})
	.strict();
export const bridgeWorkerContentAvailabilityPatchPayloadSchema = z
	.object({
		reason: z
			.enum([
				'content_unavailable',
				'descriptor_missing',
				'descriptor_rejected',
				'load_failed',
				'none',
				'source_reset',
			])
			.optional(),
		state: z.enum(['loading', 'ready', 'failed', 'stale', 'unavailable']),
	})
	.strict();
export const bridgeWorkerReviewContentMetadataSchema = z
	.object({
		itemId: z.string().min(1),
		path: z.string().min(1),
		language: z.string().nullable(),
		cacheKey: z.string().min(1),
		sizeBytes: z.number().int().nonnegative(),
		availableContentRoles: z.array(bridgeProductReviewContentRoleSchema).readonly(),
		contentLineCountsByRole: bridgeProductReviewContentLineCountsByRoleSchema,
	})
	.strict();
export const bridgeWorkerReviewContentRequestDescriptorSchema =
	bridgeProductReviewContentDescriptorSchema;
export const bridgeWorkerReviewRenderSemanticsSchema = z
	.object({
		itemId: z.string().min(1),
		itemKind: z.enum(['file', 'diff']),
		changeKind: bridgeProductReviewFileChangeKindSchema,
		displayPath: z.string().min(1),
		basePath: z.string().min(1).nullable(),
		headPath: z.string().min(1).nullable(),
		language: z.string().nullable(),
		contentLineCountsByRole: bridgeProductReviewContentLineCountsByRoleSchema,
	})
	.strict();
export const bridgeWorkerFileViewContentMetadataSchema = z
	.object({
		metadataKind: z.literal('fileView'),
		itemId: z.string().min(1),
		path: z.string().min(1),
		language: z.string().nullable(),
		cacheKey: z.string().min(1),
		sizeBytes: z.number().int().nonnegative(),
		descriptorId: z.string().min(1),
		contentHash: z.string().min(1).optional(),
		encoding: z.literal('utf-8').nullable(),
		endsMidLine: z.boolean(),
		endsWithNewline: z.boolean(),
		virtualizedExtentKind: bridgeProductFileVirtualizedExtentKindSchema,
		payloadByteCount: z.number().int().nonnegative(),
		payloadLineCount: z.number().int().nonnegative(),
		totalLineCount: z.number().int().nonnegative().nullable(),
		truncationKind: bridgeProductFileTruncationKindSchema,
		isBinary: z.boolean(),
		canFetchContent: z.boolean(),
	})
	.strict();

export type BridgeWorkerSelectionPatchPayload = z.infer<
	typeof bridgeWorkerSelectionPatchPayloadSchema
>;
export type BridgeWorkerViewportPatchPayload = z.infer<
	typeof bridgeWorkerViewportPatchPayloadSchema
>;
export type BridgeWorkerRowPaintPatchPayload = z.infer<
	typeof bridgeWorkerRowPaintPatchPayloadSchema
>;
export type BridgeWorkerContentAvailabilityPatchPayload = z.infer<
	typeof bridgeWorkerContentAvailabilityPatchPayloadSchema
>;
export type BridgeWorkerReviewContentMetadata = z.infer<
	typeof bridgeWorkerReviewContentMetadataSchema
>;
export type BridgeWorkerReviewContentRequestDescriptor = z.infer<
	typeof bridgeWorkerReviewContentRequestDescriptorSchema
>;
export type BridgeWorkerReviewRenderSemantics = z.infer<
	typeof bridgeWorkerReviewRenderSemanticsSchema
>;
export type BridgeWorkerFileViewContentMetadata = z.infer<
	typeof bridgeWorkerFileViewContentMetadataSchema
>;
export type BridgeWorkerContentMetadata =
	| BridgeWorkerFileViewContentMetadata
	| BridgeWorkerReviewContentMetadata;

export function isBridgeWorkerFileViewContentMetadata(
	metadata: BridgeWorkerContentMetadata | null,
): metadata is BridgeWorkerFileViewContentMetadata {
	return metadata !== null && bridgeWorkerFileViewContentMetadataSchema.safeParse(metadata).success;
}
