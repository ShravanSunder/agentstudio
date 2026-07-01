import { z } from 'zod';

import { bridgeDemandLaneSchema } from '../../../core/models/bridge-demand-models.js';
import { bridgeIntakeFrameBaseSchema } from '../../../core/models/bridge-intake-frame.js';
import { bridgeDescriptorRefSchema } from '../../../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../../../core/models/bridge-resource-descriptor.js';
import {
	bridgeReviewPackageSummarySchema,
	bridgeSourceEndpointSchema,
} from '../../../foundation/review-package/bridge-review-package-schema.js';
import { bridgeReviewProjectionInputItemSchema } from '../../../review-viewer/models/review-projection-models.js';

export const reviewChangesetClusterMetadataSchema = z
	.object({
		clusterId: z.string().min(1),
		sourceId: z.string().min(1),
		algorithm: z.enum([
			'explicitRange',
			'timeWindow',
			'sessionTurnBaseline',
			'checkpoint',
			'idleDebounce',
			'touchedFileAccumulation',
			'scmResourceGroup',
			'hunkGrouping',
			'manual',
			'unknown',
		]),
		lifecycle: z.enum(['live', 'closed', 'pinned']),
		confidence: z.enum(['incremental', 'freshScan', 'overflowRecovered', 'partial', 'unknown']),
		baselineCursor: z.string().min(1).optional(),
		headCursor: z.string().min(1).optional(),
		baselineRef: z.string().min(1).optional(),
		headRef: z.string().min(1).optional(),
		fromUnixMilliseconds: z.number().int().nonnegative().optional(),
		toUnixMilliseconds: z.number().int().nonnegative().optional(),
		includedPathHints: z.array(z.string().min(1)).optional(),
		groupingReason: z.string().min(1).optional(),
		limitations: z
			.array(
				z.enum([
					'shellEditsExcluded',
					'externalEditsExcluded',
					'remoteEditsExcluded',
					'ignoredPathsExcluded',
					'generatedFilesExcluded',
					'overflowRecovered',
				]),
			)
			.optional(),
	})
	.strict();

export const reviewComparisonIdentitySchema = z
	.object({
		packageId: z.string().min(1),
		sourceIdentity: z.string().min(1),
		generation: z.number().int().nonnegative(),
		revision: z.number().int().nonnegative(),
		baseEndpoint: bridgeSourceEndpointSchema,
		headEndpoint: bridgeSourceEndpointSchema,
		contentDescriptors: z.array(bridgeAttachedResourceDescriptorSchema).optional(),
		changesetCluster: reviewChangesetClusterMetadataSchema.optional(),
	})
	.strict();

export const reviewTreeRowMetadataSchema = z
	.object({
		rowId: z.string().min(1),
		itemId: z.string().min(1).optional(),
		path: z.string().min(1),
		depth: z.number().int().nonnegative(),
		isDirectory: z.boolean(),
		loaded_by: z
			.enum([
				'startup_window',
				'foreground',
				'visible',
				'nearby',
				'speculative',
				'idle',
				'delta',
				'reset',
				'replacement',
			])
			.optional(),
		lane: bridgeDemandLaneSchema.optional(),
	})
	.strict();

export const reviewExtentFactSchema = z
	.object({
		itemId: z.string().min(1),
		contentRole: z.enum(['base', 'head', 'diff', 'file']),
		lineCount: z.number().int().nonnegative(),
	})
	.strict();

export const reviewMetadataOperationSchema = z.discriminatedUnion('kind', [
	z
		.object({
			kind: z.literal('upsertItemMetadata'),
			item: bridgeReviewProjectionInputItemSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('removeItems'),
			itemIds: z.array(z.string().min(1)),
		})
		.strict(),
	z
		.object({
			kind: z.literal('appendItems'),
			items: z.array(bridgeReviewProjectionInputItemSchema),
		})
		.strict(),
	z
		.object({
			kind: z.literal('replaceItemOrder'),
			itemIds: z.array(z.string().min(1)),
		})
		.strict(),
	z
		.object({
			kind: z.literal('upsertTreeRows'),
			rows: z.array(reviewTreeRowMetadataSchema),
		})
		.strict(),
	z
		.object({
			kind: z.literal('removeTreeRows'),
			rowIds: z.array(z.string().min(1)).optional(),
			paths: z.array(z.string().min(1)).optional(),
		})
		.strict(),
	z
		.object({
			kind: z.literal('replaceTreeWindow'),
			rows: z.array(reviewTreeRowMetadataSchema),
		})
		.strict(),
	z
		.object({
			kind: z.literal('movePathPrefix'),
			fromPath: z.string().min(1),
			toPath: z.string().min(1),
			affectedItemIds: z.array(z.string().min(1)),
		})
		.strict(),
	z
		.object({
			kind: z.literal('upsertExtentFacts'),
			facts: z.array(reviewExtentFactSchema),
		})
		.strict(),
	z
		.object({
			kind: z.literal('selectItem'),
			itemId: z.string().min(1).nullable(),
		})
		.strict(),
	z
		.object({
			kind: z.literal('invalidateContentDescriptors'),
			descriptorIds: z.array(z.string().min(1)),
		})
		.strict(),
]);

export const reviewMetadataSnapshotFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('metadataSnapshot'),
		frameKind: z.literal('review.metadataSnapshot'),
		comparison: reviewComparisonIdentitySchema,
		selectedItemId: z.string().min(1).nullable(),
		visibleItemIds: z.array(z.string().min(1)),
		itemMetadata: z.array(bridgeReviewProjectionInputItemSchema),
		treeRows: z.array(reviewTreeRowMetadataSchema),
		extentFacts: z.array(reviewExtentFactSchema),
		summary: bridgeReviewPackageSummarySchema,
	})
	.strict();

export const reviewMetadataWindowFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('metadataWindow'),
		frameKind: z.literal('review.metadataWindow'),
		packageId: z.string().min(1),
		revision: z.number().int().nonnegative(),
		itemMetadata: z.array(bridgeReviewProjectionInputItemSchema),
		treeRows: z.array(reviewTreeRowMetadataSchema),
		extentFacts: z.array(reviewExtentFactSchema),
		summary: bridgeReviewPackageSummarySchema,
		contentDescriptors: z.array(bridgeAttachedResourceDescriptorSchema).optional(),
	})
	.strict();

export const reviewMetadataDeltaFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('metadataDelta'),
		frameKind: z.literal('review.metadataDelta'),
		packageId: z.string().min(1),
		fromRevision: z.number().int().nonnegative(),
		toRevision: z.number().int().nonnegative(),
		operations: z.array(reviewMetadataOperationSchema),
		summary: bridgeReviewPackageSummarySchema,
		contentDescriptors: z.array(bridgeAttachedResourceDescriptorSchema).optional(),
	})
	.strict();

export const reviewInvalidationFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('delta'),
		frameKind: z.literal('review.invalidate'),
		invalidation: z
			.object({
				scope: z.enum(['package', 'items', 'paths', 'treeWindow']),
				itemIds: z.array(z.string().min(1)).optional(),
				pathHints: z.array(z.string().min(1)).optional(),
				reason: z.enum(['sourceChanged', 'watchEvent', 'lineageReplaced', 'unknown']),
			})
			.strict(),
	})
	.strict();

export const reviewResetFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('reset'),
		frameKind: z.literal('review.reset'),
		reason: z.enum(['sourceChanged', 'subscriptionReset', 'providerRestart', 'authorityChanged']),
		sourceIdentity: z.string().min(1),
	})
	.strict();

export const reviewProtocolFrameSchema = z.discriminatedUnion('frameKind', [
	reviewMetadataSnapshotFrameSchema,
	reviewMetadataWindowFrameSchema,
	reviewMetadataDeltaFrameSchema,
	reviewInvalidationFrameSchema,
	reviewResetFrameSchema,
]);

export const reviewDemandStimulusSchema = z.discriminatedUnion('kind', [
	z
		.object({
			kind: z.literal('reviewItemSelected'),
			descriptorRef: bridgeDescriptorRefSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('reviewDescriptorInvalidated'),
			descriptorRef: bridgeDescriptorRefSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('reviewViewportChanged'),
			descriptorRefs: z.array(bridgeDescriptorRefSchema),
		})
		.strict(),
	z
		.object({
			kind: z.literal('reviewExplicitRefresh'),
			descriptorRef: bridgeDescriptorRefSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('reviewHoverChanged'),
			descriptorRef: bridgeDescriptorRefSchema.nullable(),
		})
		.strict(),
	z
		.object({
			kind: z.literal('reviewSourceReset'),
			sourceIdentity: z.string().min(1),
		})
		.strict(),
]);

export type ReviewChangesetClusterMetadata = z.infer<typeof reviewChangesetClusterMetadataSchema>;
export type ReviewComparisonIdentity = z.infer<typeof reviewComparisonIdentitySchema>;
export type ReviewTreeRowMetadata = z.infer<typeof reviewTreeRowMetadataSchema>;
export type ReviewExtentFact = z.infer<typeof reviewExtentFactSchema>;
export type ReviewMetadataOperation = z.infer<typeof reviewMetadataOperationSchema>;
export type ReviewMetadataSnapshotFrame = z.infer<typeof reviewMetadataSnapshotFrameSchema>;
export type ReviewMetadataWindowFrame = z.infer<typeof reviewMetadataWindowFrameSchema>;
export type ReviewMetadataDeltaFrame = z.infer<typeof reviewMetadataDeltaFrameSchema>;
export type ReviewInvalidationFrame = z.infer<typeof reviewInvalidationFrameSchema>;
export type ReviewResetFrame = z.infer<typeof reviewResetFrameSchema>;
export type ReviewProtocolFrame = z.infer<typeof reviewProtocolFrameSchema>;
export type ReviewDemandStimulus = z.infer<typeof reviewDemandStimulusSchema>;
