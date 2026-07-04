import { z } from 'zod';

import { bridgeDemandLaneSchema } from '../../core/models/bridge-demand-models.js';

export const bridgeContentRoleSchema = z.enum(['base', 'head', 'diff', 'file']);
export const bridgeFileClassSchema = z.enum([
	'source',
	'test',
	'docs',
	'config',
	'generated',
	'vendor',
	'binary',
	'large',
	'fixture',
	'unknown',
]);
export const bridgeFileChangeKindSchema = z.enum([
	'added',
	'modified',
	'deleted',
	'renamed',
	'copied',
]);
export const bridgeFileReviewStateSchema = z.enum([
	'unreviewed',
	'viewed',
	'annotated',
	'resolved',
]);
export const bridgeReviewPrioritySchema = z.enum(['low', 'normal', 'high']);
export const bridgeReviewProjectionWorkloadIdSchema = z.enum([
	'interactive',
	'bridge_viewer_medium_review_v1',
	'bridge_viewer_large_tree_v1',
	'bridge_viewer_large_diff_scroll_v1',
]);

export type BridgeReviewProjectionWorkloadId = z.infer<
	typeof bridgeReviewProjectionWorkloadIdSchema
>;

export const bridgeCurrentChangeSetScopeSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('activePackage') }),
	z.object({
		kind: z.literal('provenance'),
		provenanceKind: z.enum(['prompt', 'session', 'operation']),
		provenanceId: z.string().min(1),
	}),
]);

export type BridgeCurrentChangeSetScope = z.infer<typeof bridgeCurrentChangeSetScopeSchema>;

export const bridgeReviewFacetCountsSchema = z.object({
	fileClasses: z.record(z.string(), z.number().int().nonnegative()),
	extensions: z.record(z.string(), z.number().int().nonnegative()),
	changeKinds: z.record(z.string(), z.number().int().nonnegative()),
	reviewStates: z.record(z.string(), z.number().int().nonnegative()),
	hidden: z.number().int().nonnegative(),
	binary: z.number().int().nonnegative(),
	large: z.number().int().nonnegative(),
});

export type BridgeReviewFacetCounts = z.infer<typeof bridgeReviewFacetCountsSchema>;

export const bridgeReviewProjectionFacetSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('folder'), folderPath: z.string().min(1) }),
	z.object({ kind: z.literal('extension'), extensions: z.array(z.string().min(1)).readonly() }),
	z.object({ kind: z.literal('language'), languages: z.array(z.string().min(1)).readonly() }),
	z.object({ kind: z.literal('mime'), mimeTypes: z.array(z.string().min(1)).readonly() }),
	z.object({
		kind: z.literal('fileClass'),
		fileClasses: z.array(bridgeFileClassSchema).readonly(),
	}),
	z.object({
		kind: z.literal('gitStatus'),
		statuses: z.array(bridgeFileChangeKindSchema).readonly(),
	}),
	z.object({ kind: z.literal('changeScope'), scope: bridgeCurrentChangeSetScopeSchema }),
	z.object({
		kind: z.literal('visibility'),
		includeHidden: z.boolean(),
		includeBinary: z.boolean(),
		includeLarge: z.boolean(),
	}),
]);

export type BridgeReviewProjectionFacet = z.infer<typeof bridgeReviewProjectionFacetSchema>;

export const bridgeReviewProjectionItemProvenanceSchema = z.object({
	promptIds: z.array(z.string()).readonly(),
	agentSessionIds: z.array(z.string()).readonly(),
	operationIds: z.array(z.string()).readonly(),
});

export type BridgeReviewProjectionItemProvenance = z.infer<
	typeof bridgeReviewProjectionItemProvenanceSchema
>;

export const bridgeReviewProjectionInputItemSchema = z.object({
	itemId: z.string().min(1),
	basePath: z.string().min(1).nullable(),
	headPath: z.string().min(1).nullable(),
	changeKind: bridgeFileChangeKindSchema,
	fileClass: bridgeFileClassSchema,
	language: z
		.string()
		.min(1)
		.nullish()
		.transform((value): string | null => value ?? null),
	extension: z
		.string()
		.min(1)
		.nullish()
		.transform((value): string | null => value ?? null),
	isHiddenByDefault: z.boolean(),
	reviewPriority: bridgeReviewPrioritySchema,
	reviewState: bridgeFileReviewStateSchema,
	contentRoles: z.array(bridgeContentRoleSchema).readonly(),
	contentDescriptorIdsByRole: z
		.object({
			base: z.string().min(1).nullable().optional(),
			head: z.string().min(1).nullable().optional(),
			diff: z.string().min(1).nullable().optional(),
			file: z.string().min(1).nullable().optional(),
		})
		.strict()
		.optional(),
	contentHashesByRole: z
		.object({
			base: z.string().min(1).nullable().optional(),
			head: z.string().min(1).nullable().optional(),
			diff: z.string().min(1).nullable().optional(),
			file: z.string().min(1).nullable().optional(),
		})
		.strict()
		.optional(),
	mimeTypes: z.array(z.string().min(1)).readonly(),
	provenance: bridgeReviewProjectionItemProvenanceSchema,
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
});

export type BridgeReviewProjectionInputItem = z.infer<typeof bridgeReviewProjectionInputItemSchema>;

export const bridgeReviewProjectionInputSchema = z.object({
	packageId: z.string().min(1),
	reviewGeneration: z.number().int().nonnegative(),
	revision: z.number().int().nonnegative(),
	orderedItems: z.array(bridgeReviewProjectionInputItemSchema).readonly(),
});

export type BridgeReviewProjectionInput = z.infer<typeof bridgeReviewProjectionInputSchema>;

export const bridgeReviewProjectionResultSchema = z.object({
	projectionId: z.string().min(1),
	label: z.string().min(1),
	orderedItemIds: z.array(z.string().min(1)).readonly(),
	orderedPaths: z.array(z.string()).readonly(),
	primaryDisplayPathByItemId: z.record(z.string(), z.string()),
	primaryItemIdByTreePath: z.record(z.string(), z.string()),
	secondaryItemIdsByTreePath: z.record(z.string(), z.array(z.string()).readonly()),
	candidatePathsByItemId: z.record(z.string(), z.array(z.string()).readonly()),
	itemIdsByDisplayPath: z.record(z.string(), z.array(z.string()).readonly()),
	availableContentRolesByItemId: z.record(z.string(), z.array(bridgeContentRoleSchema).readonly()),
	facetCounts: bridgeReviewFacetCountsSchema,
});

export type BridgeReviewProjectionResult = z.infer<typeof bridgeReviewProjectionResultSchema>;

export const bridgeReviewProjectionModeSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('normalReview') }),
	z.object({ kind: z.literal('guidedReview') }),
	z.object({ kind: z.literal('plansAndSpecs') }),
]);

export type BridgeReviewProjectionMode = z.infer<typeof bridgeReviewProjectionModeSchema>;

export const bridgeReviewRenderModeSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('codeView') }),
	z.object({ kind: z.literal('markdownPreview') }),
]);

export type BridgeReviewRenderMode = z.infer<typeof bridgeReviewRenderModeSchema>;

export const bridgeReviewSearchModeSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('text') }),
	z.object({ kind: z.literal('regex') }),
]);

export type BridgeReviewSearchMode = z.infer<typeof bridgeReviewSearchModeSchema>;

export const bridgeReviewFilterStateSchema = z.object({
	treeSearchText: z.string(),
	treeSearchMode: bridgeReviewSearchModeSchema,
	gitStatusFilter: z.union([z.literal('all'), bridgeFileChangeKindSchema]),
	fileClassFilter: z.union([z.literal('all'), bridgeFileClassSchema]),
});

export type BridgeReviewFilterState = z.infer<typeof bridgeReviewFilterStateSchema>;

export const bridgeReviewProjectionRequestSchema = z.object({
	mode: bridgeReviewProjectionModeSchema,
	facets: z.array(bridgeReviewProjectionFacetSchema).readonly(),
});

export type BridgeReviewProjectionRequest = z.infer<typeof bridgeReviewProjectionRequestSchema>;

export const bridgeReviewProjectionRequestIdentitySchema = z.object({
	requestId: z.string().min(1),
	packageId: z.string().min(1),
	reviewGeneration: z.number().int().nonnegative(),
	revision: z.number().int().nonnegative(),
	projectionRequestFingerprint: z.string().min(1),
	abortKey: z.string().min(1).optional(),
});

export type BridgeReviewProjectionRequestIdentity = z.infer<
	typeof bridgeReviewProjectionRequestIdentitySchema
>;

export const bridgeReviewProjectionSchema = bridgeReviewProjectionRequestSchema.and(
	bridgeReviewProjectionResultSchema,
);

export type BridgeReviewProjection = z.infer<typeof bridgeReviewProjectionSchema>;
