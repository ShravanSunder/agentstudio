import { z } from 'zod';

import { bridgeIntakeFrameBaseSchema } from '../../../core/models/bridge-intake-frame.js';
import { bridgeDescriptorRefSchema } from '../../../core/models/bridge-resource-descriptor.js';
import { bridgeAttachedResourceDescriptorSchema } from '../../../core/models/bridge-resource-descriptor.js';

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

export const reviewPackageIdentitySchema = z
	.object({
		packageId: z.string().min(1),
		sourceIdentity: z.string().min(1),
		generation: z.number().int().nonnegative(),
		revision: z.number().int().nonnegative(),
		rootDescriptor: bridgeAttachedResourceDescriptorSchema,
		contentDescriptors: z.array(bridgeAttachedResourceDescriptorSchema).optional(),
		changesetCluster: reviewChangesetClusterMetadataSchema.optional(),
	})
	.strict();

export const reviewSnapshotFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('snapshot'),
		frameKind: z.literal('review.snapshot'),
		package: reviewPackageIdentitySchema,
	})
	.strict();

export const reviewDeltaFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('delta'),
		frameKind: z.literal('review.delta'),
		packageId: z.string().min(1),
		fromRevision: z.number().int().nonnegative(),
		toRevision: z.number().int().nonnegative(),
		operationsDescriptor: bridgeAttachedResourceDescriptorSchema,
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
		packageId: z.string().min(1).optional(),
		replacementDescriptor: bridgeAttachedResourceDescriptorSchema.optional(),
	})
	.strict();

export const reviewProtocolFrameSchema = z.discriminatedUnion('frameKind', [
	reviewSnapshotFrameSchema,
	reviewDeltaFrameSchema,
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
			packageId: z.string().min(1).optional(),
		})
		.strict(),
]);

export type ReviewChangesetClusterMetadata = z.infer<typeof reviewChangesetClusterMetadataSchema>;
export type ReviewSnapshotFrame = z.infer<typeof reviewSnapshotFrameSchema>;
export type ReviewDeltaFrame = z.infer<typeof reviewDeltaFrameSchema>;
export type ReviewInvalidationFrame = z.infer<typeof reviewInvalidationFrameSchema>;
export type ReviewResetFrame = z.infer<typeof reviewResetFrameSchema>;
export type ReviewProtocolFrame = z.infer<typeof reviewProtocolFrameSchema>;
export type ReviewDemandStimulus = z.infer<typeof reviewDemandStimulusSchema>;
