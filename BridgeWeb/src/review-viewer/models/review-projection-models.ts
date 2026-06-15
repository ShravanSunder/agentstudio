import { z } from 'zod';

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

export const bridgeReviewProjectionRefinementSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('folder'), folderPath: z.string().min(1) }),
	z.object({ kind: z.literal('extension'), extensions: z.array(z.string().min(1)) }),
	z.object({ kind: z.literal('language'), languages: z.array(z.string().min(1)) }),
	z.object({ kind: z.literal('mime'), mimeTypes: z.array(z.string().min(1)) }),
	z.object({ kind: z.literal('fileClass'), fileClasses: z.array(bridgeFileClassSchema) }),
	z.object({ kind: z.literal('gitStatus'), statuses: z.array(bridgeFileChangeKindSchema) }),
	z.object({
		kind: z.literal('visibility'),
		includeHidden: z.boolean(),
		includeBinary: z.boolean(),
		includeLarge: z.boolean(),
	}),
]);

export type BridgeReviewProjectionRefinement = z.infer<
	typeof bridgeReviewProjectionRefinementSchema
>;

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
	language: z.string().min(1).nullable(),
	extension: z.string().min(1).nullable(),
	isHiddenByDefault: z.boolean(),
	reviewPriority: bridgeReviewPrioritySchema,
	reviewState: bridgeFileReviewStateSchema,
	contentRoles: z.array(bridgeContentRoleSchema).readonly(),
	mimeTypes: z.array(z.string().min(1)).readonly(),
	provenance: bridgeReviewProjectionItemProvenanceSchema,
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
	z.object({ kind: z.literal('allFiles') }),
	z.object({ kind: z.literal('changedFiles') }),
	z.object({ kind: z.literal('guidedReview') }),
	z.object({
		kind: z.literal('currentChangeSet'),
		scope: bridgeCurrentChangeSetScopeSchema,
	}),
	z.object({ kind: z.literal('docsAndPlans') }),
	z.object({ kind: z.literal('tests') }),
	z.object({ kind: z.literal('source') }),
	z.object({ kind: z.literal('custom'), customProjectionId: z.string().min(1) }),
]);

export type BridgeReviewProjectionMode = z.infer<typeof bridgeReviewProjectionModeSchema>;

export const bridgeReviewProjectionRequestSchema = z.object({
	base: bridgeReviewProjectionModeSchema,
	refinements: z.array(bridgeReviewProjectionRefinementSchema).readonly(),
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
