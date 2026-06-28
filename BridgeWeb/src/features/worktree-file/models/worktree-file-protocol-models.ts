import { z } from 'zod';

import { bridgeIntakeFrameBaseSchema } from '../../../core/models/bridge-intake-frame.js';
import {
	bridgeAttachedResourceDescriptorSchema,
	bridgeDescriptorRefSchema,
} from '../../../core/models/bridge-resource-descriptor.js';

export const worktreeFileSurfaceSourceSpecSchema = z
	.object({
		clientRequestId: z.string().min(1),
		repoId: z.string().min(1),
		worktreeId: z.string().min(1),
		rootPathToken: z.string().min(1),
		cwdScope: z.string().min(1).optional(),
		pathScope: z.array(z.string().min(1)).optional(),
		includeStatuses: z.boolean().default(true),
		includeFileDescriptors: z.boolean().default(true),
		includeComments: z.boolean().default(false),
		includeAgentComms: z.boolean().default(false),
		freshness: z.literal('live'),
	})
	.strict();

export const worktreeFileSurfaceOpenSourceOutcomeSchema = z
	.object({
		status: z.literal('accepted'),
		protocol: z.literal('worktree-file'),
		streamId: z.string().min(1),
		generation: z.number().int().nonnegative(),
	})
	.strict();

export const worktreeFileSurfaceSourceIdentitySchema = z
	.object({
		sourceId: z.string().min(1),
		repoId: z.string().min(1),
		worktreeId: z.string().min(1),
		subscriptionGeneration: z.number().int().nonnegative(),
		sourceCursor: z.string().min(1),
		rootRevisionToken: z.string().min(1).optional(),
	})
	.strict();

export const worktreeTreeProjectionIdentitySchema = z
	.object({
		source: worktreeFileSurfaceSourceIdentitySchema,
		pathScope: z.array(z.string().min(1)),
		sortKey: z.string().min(1).optional(),
		groupKey: z.string().min(1).optional(),
		filterKey: z.string().min(1).optional(),
		treeWindowKey: z.string().min(1).optional(),
	})
	.strict();

export const worktreeTreeVirtualizedSizeFactsSchema = z
	.object({
		pathCount: z.number().int().nonnegative().optional(),
		windowStartIndex: z.number().int().nonnegative().optional(),
		windowRowCount: z.number().int().nonnegative().optional(),
		rowHeightPixels: z.number().positive(),
		estimatedTotalHeightPixels: z.number().nonnegative().optional(),
	})
	.strict()
	.superRefine((facts, context): void => {
		if (facts.pathCount === undefined && facts.estimatedTotalHeightPixels === undefined) {
			context.addIssue({
				code: 'custom',
				message: 'tree size facts require pathCount or estimatedTotalHeightPixels',
				path: ['pathCount'],
			});
		}
	});

export const worktreeFileVirtualizedExtentKindSchema = z.enum([
	'exactLineCount',
	'estimatedHeight',
	'previewBounded',
	'unavailable',
]);

export const worktreeFileSurfaceResourceKindSchema = z.enum([
	'worktree.treeWindow',
	'worktree.treeDeltaOperations',
	'worktree.status',
	'worktree.fileContent',
	'worktree.fileRange',
	'worktree.commentThreadWindow',
	'worktree.agentCommsWindow',
]);

export const worktreeFileDescriptorSchema = z
	.object({
		path: z.string().min(1),
		fileId: z.string().min(1),
		contentHandle: z.string().min(1),
		contentDescriptor: bridgeAttachedResourceDescriptorSchema,
		contentHash: z.string().min(1).optional(),
		sourceIdentity: worktreeFileSurfaceSourceIdentitySchema,
		sizeBytes: z.number().int().nonnegative(),
		virtualizedExtentKind: worktreeFileVirtualizedExtentKindSchema,
		lineCount: z.number().int().nonnegative().optional(),
		estimatedContentHeightPixels: z.number().nonnegative().optional(),
		isBinary: z.boolean(),
		language: z.string().min(1).optional(),
		fileExtension: z.string().min(1).optional(),
		modifiedAtUnixMilliseconds: z.number().int().nonnegative().optional(),
	})
	.strict()
	.superRefine((descriptor, context): void => {
		if (
			descriptor.virtualizedExtentKind === 'exactLineCount' &&
			descriptor.lineCount === undefined
		) {
			context.addIssue({
				code: 'custom',
				message: 'exactLineCount descriptors require lineCount',
				path: ['lineCount'],
			});
		}
		if (
			descriptor.virtualizedExtentKind === 'estimatedHeight' &&
			descriptor.estimatedContentHeightPixels === undefined
		) {
			context.addIssue({
				code: 'custom',
				message: 'estimatedHeight descriptors require estimatedContentHeightPixels',
				path: ['estimatedContentHeightPixels'],
			});
		}
	});

export const worktreeOpenFileSessionStatusSchema = z.enum([
	'opening',
	'fresh',
	'stale',
	'refreshing',
	'failed',
	'closed',
]);

export const worktreeOpenFileStaleReasonSchema = z.enum([
	'filesystemEvent',
	'gitStatusChanged',
	'contentChanged',
	'sourceReset',
	'unknown',
]);

export const worktreeStatusPatchSchema = z
	.object({
		path: z.string().min(1).optional(),
		status: z.string().min(1).optional(),
		staged: z.number().int().nonnegative().optional(),
		unstaged: z.number().int().nonnegative().optional(),
		untracked: z.number().int().nonnegative().optional(),
		branchName: z.string().min(1).optional(),
		ahead: z.number().int().nonnegative().optional(),
		behind: z.number().int().nonnegative().optional(),
	})
	.strict();

export const worktreeFileInvalidationSchema = z
	.object({
		path: z.string().min(1),
		fileId: z.string().min(1).optional(),
		reason: worktreeOpenFileStaleReasonSchema,
		contentHandleIds: z.array(z.string().min(1)).optional(),
		latestDescriptor: worktreeFileDescriptorSchema.optional(),
	})
	.strict();

export const worktreeSnapshotFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('snapshot'),
		frameKind: z.literal('worktree.snapshot'),
		source: worktreeFileSurfaceSourceIdentitySchema,
		requestSelector: worktreeFileSurfaceSourceSpecSchema.optional(),
		treeDescriptor: bridgeAttachedResourceDescriptorSchema,
		treeSizeFacts: worktreeTreeVirtualizedSizeFactsSchema.optional(),
		statusDescriptor: bridgeAttachedResourceDescriptorSchema.optional(),
	})
	.strict();

export const worktreeTreeWindowFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('delta'),
		frameKind: z.literal('worktree.treeWindow'),
		projectionIdentity: worktreeTreeProjectionIdentitySchema,
		windowDescriptor: bridgeAttachedResourceDescriptorSchema,
		treeSizeFacts: worktreeTreeVirtualizedSizeFactsSchema.optional(),
	})
	.strict();

export const worktreeTreeDeltaFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('delta'),
		frameKind: z.literal('worktree.treeDelta'),
		operationsDescriptor: bridgeAttachedResourceDescriptorSchema,
	})
	.strict();

export const worktreeStatusPatchFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('delta'),
		frameKind: z.literal('worktree.statusPatch'),
		patch: z.union([
			worktreeStatusPatchSchema,
			z
				.object({
					statusDescriptor: bridgeAttachedResourceDescriptorSchema,
				})
				.strict(),
		]),
	})
	.strict();

export const worktreeFileDescriptorFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('delta'),
		frameKind: z.literal('worktree.fileDescriptor'),
		descriptor: worktreeFileDescriptorSchema,
	})
	.strict();

export const worktreeFileInvalidatedFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('delta'),
		frameKind: z.literal('worktree.fileInvalidated'),
		invalidation: worktreeFileInvalidationSchema,
	})
	.strict();

export const worktreeResetFrameSchema = bridgeIntakeFrameBaseSchema
	.extend({
		kind: z.literal('reset'),
		frameKind: z.literal('worktree.reset'),
		reason: z.enum(['sourceChanged', 'subscriptionReset', 'providerRestart', 'authorityChanged']),
		source: worktreeFileSurfaceSourceIdentitySchema.optional(),
		replacementDescriptor: bridgeAttachedResourceDescriptorSchema.optional(),
	})
	.strict();

export const worktreeFileProtocolFrameSchema = z.discriminatedUnion('frameKind', [
	worktreeSnapshotFrameSchema,
	worktreeTreeWindowFrameSchema,
	worktreeTreeDeltaFrameSchema,
	worktreeStatusPatchFrameSchema,
	worktreeFileDescriptorFrameSchema,
	worktreeFileInvalidatedFrameSchema,
	worktreeResetFrameSchema,
]);

export const worktreeFileDemandStimulusSchema = z.discriminatedUnion('kind', [
	z
		.object({
			kind: z.literal('fileSelected'),
			descriptorRef: bridgeDescriptorRefSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('openFileInvalidated'),
			descriptorRef: bridgeDescriptorRefSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('treeViewportChanged'),
			descriptorRefs: z.array(bridgeDescriptorRefSchema),
		})
		.strict(),
	z
		.object({
			kind: z.literal('treeExpanded'),
			descriptorRef: bridgeDescriptorRefSchema,
			nearbyDescriptorRefs: z.array(bridgeDescriptorRefSchema).optional(),
		})
		.strict(),
	z
		.object({
			kind: z.literal('explicitRefresh'),
			descriptorRef: bridgeDescriptorRefSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('hoverChanged'),
			descriptorRef: bridgeDescriptorRefSchema.nullable(),
		})
		.strict(),
	z
		.object({
			kind: z.literal('recentlyUpdatedFile'),
			descriptorRef: bridgeDescriptorRefSchema,
			proximity: z.enum(['nearby', 'remote']),
			sourceIdentity: z.string().min(1),
		})
		.strict(),
	z
		.object({
			kind: z.literal('sourceReset'),
			sourceIdentity: z.string().min(1),
		})
		.strict(),
]);

export type WorktreeFileSurfaceSourceSpec = z.infer<typeof worktreeFileSurfaceSourceSpecSchema>;
export type WorktreeFileSurfaceSourceIdentity = z.infer<
	typeof worktreeFileSurfaceSourceIdentitySchema
>;
export type WorktreeTreeProjectionIdentity = z.infer<typeof worktreeTreeProjectionIdentitySchema>;
export type WorktreeTreeVirtualizedSizeFacts = z.infer<
	typeof worktreeTreeVirtualizedSizeFactsSchema
>;
export type WorktreeFileVirtualizedExtentKind = z.infer<
	typeof worktreeFileVirtualizedExtentKindSchema
>;
export type WorktreeFileSurfaceResourceKind = z.infer<typeof worktreeFileSurfaceResourceKindSchema>;
export type WorktreeFileDescriptor = z.infer<typeof worktreeFileDescriptorSchema>;

export function canFetchWorktreeFileDescriptorContent(descriptor: WorktreeFileDescriptor): boolean {
	return !descriptor.isBinary && descriptor.virtualizedExtentKind !== 'unavailable';
}
export type WorktreeOpenFileSessionStatus = z.infer<typeof worktreeOpenFileSessionStatusSchema>;
export type WorktreeOpenFileStaleReason = z.infer<typeof worktreeOpenFileStaleReasonSchema>;
export type WorktreeStatusPatch = z.infer<typeof worktreeStatusPatchSchema>;
export type WorktreeFileInvalidation = z.infer<typeof worktreeFileInvalidationSchema>;
export type WorktreeSnapshotFrame = z.infer<typeof worktreeSnapshotFrameSchema>;
export type WorktreeTreeWindowFrame = z.infer<typeof worktreeTreeWindowFrameSchema>;
export type WorktreeTreeDeltaFrame = z.infer<typeof worktreeTreeDeltaFrameSchema>;
export type WorktreeStatusPatchFrame = z.infer<typeof worktreeStatusPatchFrameSchema>;
export type WorktreeFileDescriptorFrame = z.infer<typeof worktreeFileDescriptorFrameSchema>;
export type WorktreeFileInvalidatedFrame = z.infer<typeof worktreeFileInvalidatedFrameSchema>;
export type WorktreeResetFrame = z.infer<typeof worktreeResetFrameSchema>;
export type WorktreeFileProtocolFrame = z.infer<typeof worktreeFileProtocolFrameSchema>;
export type WorktreeFileDemandStimulus = z.infer<typeof worktreeFileDemandStimulusSchema>;
