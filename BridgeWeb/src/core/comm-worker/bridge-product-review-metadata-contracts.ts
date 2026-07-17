import { z } from 'zod';

import { bridgeProductReviewContentSourceDescriptorSchema } from './bridge-product-content-contracts.js';
import {
	bridgeProductDemandLaneSchema,
	bridgeProductDisplayPathSchema,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductOpaqueReferenceSchema,
	bridgeProductSafeMessageSchema,
} from './bridge-product-contract-primitives.js';
import {
	bridgeProductReviewContentRoleSchema,
	bridgeProductReviewFileChangeKindSchema,
	bridgeProductReviewFileClassSchema,
	bridgeProductReviewFileStateSchema,
	bridgeProductReviewGroupingKindSchema,
	bridgeProductReviewPackageSummarySchema,
	bridgeProductReviewPrioritySchema,
	bridgeProductReviewPublicationIdSchema,
	bridgeProductReviewSourceEndpointKindSchema,
} from './bridge-product-review-primitives.js';

const bridgeProductReviewMetadataLoadedBySchema = z.enum([
	'startup_window',
	'foreground',
	'visible',
	'nearby',
	'speculative',
	'idle',
	'delta',
	'reset',
	'replacement',
]);

export const BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT = 4_096;

const bridgeProductReviewItemWindowSchema = z
	.object({
		finalWindow: z.boolean(),
		itemCount: bridgeProductNonnegativeSequenceSchema.max(
			BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT,
		),
		startIndex: bridgeProductNonnegativeSequenceSchema,
		totalItemCount: bridgeProductNonnegativeSequenceSchema,
	})
	.strict()
	.superRefine((window, context): void => {
		validateOrderedReviewWindow({
			context,
			count: window.itemCount,
			countPath: ['itemCount'],
			finalWindow: window.finalWindow,
			startIndex: window.startIndex,
			totalCount: window.totalItemCount,
			totalCountPath: ['totalItemCount'],
		});
	});

const bridgeProductReviewTreeWindowSchema = z
	.object({
		finalWindow: z.boolean(),
		rowCount: bridgeProductNonnegativeSequenceSchema.max(
			BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT,
		),
		startIndex: bridgeProductNonnegativeSequenceSchema,
		totalRowCount: bridgeProductNonnegativeSequenceSchema,
	})
	.strict()
	.superRefine((window, context): void => {
		validateOrderedReviewWindow({
			context,
			count: window.rowCount,
			countPath: ['rowCount'],
			finalWindow: window.finalWindow,
			startIndex: window.startIndex,
			totalCount: window.totalRowCount,
			totalCountPath: ['totalRowCount'],
		});
	});

export const bridgeProductReviewSourceEndpointSchema = z
	.object({
		contentSetHash: bridgeProductOpaqueReferenceSchema.nullable().optional(),
		createdAtUnixMilliseconds: bridgeProductNonnegativeSequenceSchema,
		endpointId: bridgeProductIdentifierSchema,
		kind: bridgeProductReviewSourceEndpointKindSchema,
		label: bridgeProductSafeMessageSchema,
		providerIdentity: bridgeProductOpaqueReferenceSchema,
		repoId: bridgeProductIdentifierSchema,
		worktreeId: bridgeProductIdentifierSchema,
	})
	.strict();

const bridgeProductReviewViewFilterSchema = z
	.object({
		changeKinds: z.array(bridgeProductReviewFileChangeKindSchema).max(5).readonly(),
		excludedExtensions: z.array(bridgeProductOpaqueReferenceSchema).max(256).readonly(),
		excludedFileClasses: z.array(bridgeProductReviewFileClassSchema).max(10).readonly(),
		excludedPathGlobs: z.array(bridgeProductDisplayPathSchema).max(256).readonly(),
		includedExtensions: z.array(bridgeProductOpaqueReferenceSchema).max(256).readonly(),
		includedFileClasses: z.array(bridgeProductReviewFileClassSchema).max(10).readonly(),
		includedPathGlobs: z.array(bridgeProductDisplayPathSchema).max(256).readonly(),
		reviewStates: z.array(bridgeProductReviewFileStateSchema).max(4).readonly(),
		showBinaryFiles: z.boolean(),
		showHiddenFiles: z.boolean(),
		showLargeFiles: z.boolean(),
	})
	.strict();

export const bridgeProductReviewQuerySchema = z
	.object({
		baseEndpointId: bridgeProductIdentifierSchema.nullable(),
		comparisonSemantics: z.enum([
			'twoDot',
			'threeDot',
			'checkpointDelta',
			'indexDelta',
			'workingTreeDelta',
			'notApplicable',
		]),
		fileTarget: bridgeProductDisplayPathSchema.nullable(),
		grouping: z
			.object({
				kind: bridgeProductReviewGroupingKindSchema,
				label: bridgeProductSafeMessageSchema.nullable().optional(),
			})
			.strict(),
		headEndpointId: bridgeProductIdentifierSchema.nullable(),
		pathScope: z.array(bridgeProductDisplayPathSchema).max(10_000).readonly(),
		provenanceFilter: z
			.object({
				agentSessionIds: z.array(bridgeProductIdentifierSchema).max(1024).readonly(),
				createdAfterUnixMilliseconds: bridgeProductNonnegativeSequenceSchema.nullable().optional(),
				createdBeforeUnixMilliseconds: bridgeProductNonnegativeSequenceSchema.nullable().optional(),
				operationIds: z.array(bridgeProductIdentifierSchema).max(1024).readonly(),
				paneIds: z.array(bridgeProductIdentifierSchema).max(1024).readonly(),
				promptIds: z.array(bridgeProductIdentifierSchema).max(1024).readonly(),
				sourceKinds: z.array(bridgeProductOpaqueReferenceSchema).max(64).readonly(),
			})
			.strict(),
		queryId: bridgeProductIdentifierSchema,
		queryKind: z.enum(['compare', 'openFile', 'browseTree', 'filterPackage', 'groupPackage']),
		repoId: bridgeProductIdentifierSchema,
		viewFilter: bridgeProductReviewViewFilterSchema,
		worktreeId: bridgeProductIdentifierSchema,
	})
	.strict();

export const bridgeProductReviewItemMetadataSchema = z
	.object({
		basePath: bridgeProductDisplayPathSchema.nullable(),
		changeKind: bridgeProductReviewFileChangeKindSchema,
		contentDescriptorIdsByRole: z
			.object({
				base: bridgeProductIdentifierSchema.nullable().optional(),
				diff: bridgeProductIdentifierSchema.nullable().optional(),
				file: bridgeProductIdentifierSchema.nullable().optional(),
				head: bridgeProductIdentifierSchema.nullable().optional(),
			})
			.strict(),
		contentHashesByRole: z
			.object({
				base: bridgeProductOpaqueReferenceSchema.nullable().optional(),
				diff: bridgeProductOpaqueReferenceSchema.nullable().optional(),
				file: bridgeProductOpaqueReferenceSchema.nullable().optional(),
				head: bridgeProductOpaqueReferenceSchema.nullable().optional(),
			})
			.strict(),
		contentRoles: z.array(bridgeProductReviewContentRoleSchema).readonly(),
		extension: bridgeProductOpaqueReferenceSchema.nullable(),
		fileClass: bridgeProductReviewFileClassSchema,
		headPath: bridgeProductDisplayPathSchema.nullable(),
		isHiddenByDefault: z.boolean(),
		itemId: bridgeProductIdentifierSchema,
		lane: bridgeProductDemandLaneSchema.optional(),
		language: bridgeProductOpaqueReferenceSchema.nullable(),
		loadedBy: bridgeProductReviewMetadataLoadedBySchema.optional(),
		mimeTypes: z.array(bridgeProductOpaqueReferenceSchema).readonly(),
		provenance: z
			.object({
				agentSessionIds: z.array(bridgeProductIdentifierSchema).readonly(),
				operationIds: z.array(bridgeProductIdentifierSchema).readonly(),
				promptIds: z.array(bridgeProductIdentifierSchema).readonly(),
			})
			.strict(),
		reviewPriority: bridgeProductReviewPrioritySchema,
		reviewState: bridgeProductReviewFileStateSchema,
	})
	.strict();

export const bridgeProductReviewTreeRowSchema = z
	.object({
		depth: bridgeProductNonnegativeSequenceSchema,
		isDirectory: z.boolean(),
		itemId: bridgeProductIdentifierSchema.nullable(),
		lane: bridgeProductDemandLaneSchema.optional(),
		loadedBy: bridgeProductReviewMetadataLoadedBySchema.optional(),
		path: bridgeProductDisplayPathSchema,
		rowId: bridgeProductIdentifierSchema,
	})
	.strict();

export const bridgeProductReviewExtentFactSchema = z
	.object({
		contentRole: bridgeProductReviewContentRoleSchema,
		itemId: bridgeProductIdentifierSchema,
		lineCount: bridgeProductNonnegativeSequenceSchema,
	})
	.strict();

const bridgeProductReviewMetadataIdentityShape = {
	generation: bridgeProductNonnegativeSequenceSchema,
	packageId: bridgeProductIdentifierSchema,
	publicationId: bridgeProductReviewPublicationIdSchema,
	revision: bridgeProductNonnegativeSequenceSchema,
	sourceIdentity: bridgeProductIdentifierSchema,
} as const;

export const bridgeProductReviewSourceAcceptedEventSchema = z
	.object({
		...bridgeProductReviewMetadataIdentityShape,
		eventKind: z.literal('review.sourceAccepted'),
	})
	.strict();

const bridgeProductReviewMetadataOperationSchema = z.discriminatedUnion('operationKind', [
	z
		.object({
			item: bridgeProductReviewItemMetadataSchema,
			operationKind: z.literal('upsertItem'),
		})
		.strict(),
	z
		.object({
			itemIds: z
				.array(bridgeProductIdentifierSchema)
				.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
				.refine(
					(itemIds) => new Set(itemIds).size === itemIds.length,
					'Review removed item identities must be unique.',
				)
				.readonly(),
			operationKind: z.literal('removeItems'),
		})
		.strict(),
	z
		.object({
			itemIds: z
				.array(bridgeProductIdentifierSchema)
				.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
				.refine(
					(itemIds) => new Set(itemIds).size === itemIds.length,
					'Review replacement item order must contain unique identities.',
				)
				.readonly(),
			operationKind: z.literal('replaceItemOrder'),
		})
		.strict(),
	z
		.object({
			deleteCount: bridgeProductNonnegativeSequenceSchema.max(
				BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT,
			),
			operationKind: z.literal('spliceTreeRows'),
			rows: z
				.array(bridgeProductReviewTreeRowSchema)
				.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
				.readonly(),
			startIndex: bridgeProductNonnegativeSequenceSchema,
		})
		.strict(),
	z
		.object({
			facts: z
				.array(bridgeProductReviewExtentFactSchema)
				.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
				.readonly(),
			operationKind: z.literal('upsertExtentFacts'),
		})
		.strict(),
	z
		.object({
			descriptorIds: z
				.array(bridgeProductIdentifierSchema)
				.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
				.readonly(),
			operationKind: z.literal('invalidateContentSources'),
		})
		.strict(),
]);

const bridgeProductReviewMetadataPayloadShape = {
	contentSources: z
		.array(bridgeProductReviewContentSourceDescriptorSchema)
		.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
		.readonly(),
	extentFacts: z
		.array(bridgeProductReviewExtentFactSchema)
		.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
		.readonly(),
	itemMetadata: z
		.array(bridgeProductReviewItemMetadataSchema)
		.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
		.readonly(),
	summary: bridgeProductReviewPackageSummarySchema,
	treeRows: z
		.array(bridgeProductReviewTreeRowSchema)
		.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
		.readonly(),
} as const;

export const bridgeProductReviewMetadataSnapshotEventSchema = z
	.object({
		...bridgeProductReviewMetadataIdentityShape,
		...bridgeProductReviewMetadataPayloadShape,
		baseEndpoint: bridgeProductReviewSourceEndpointSchema,
		eventKind: z.literal('review.snapshot'),
		headEndpoint: bridgeProductReviewSourceEndpointSchema,
		itemWindow: bridgeProductReviewItemWindowSchema,
		query: bridgeProductReviewQuerySchema,
		treeWindow: bridgeProductReviewTreeWindowSchema,
	})
	.strict()
	.superRefine((event, context): void => {
		validateReviewMetadataWindowPayload(event, context);
		if (event.itemWindow.startIndex !== 0) {
			context.addIssue({
				code: 'custom',
				message: 'Review metadata snapshots must start the ordered item window at zero.',
				path: ['itemWindow', 'startIndex'],
			});
		}
		if (event.treeWindow.startIndex !== 0) {
			context.addIssue({
				code: 'custom',
				message: 'Review metadata snapshots must start the ordered tree window at zero.',
				path: ['treeWindow', 'startIndex'],
			});
		}
	});

export const bridgeProductReviewMetadataWindowEventSchema = z
	.object({
		...bridgeProductReviewMetadataIdentityShape,
		...bridgeProductReviewMetadataPayloadShape,
		eventKind: z.literal('review.window'),
		itemWindow: bridgeProductReviewItemWindowSchema,
		treeWindow: bridgeProductReviewTreeWindowSchema,
	})
	.strict()
	.superRefine((event, context): void => {
		validateReviewMetadataWindowPayload(event, context);
	});

export const bridgeProductReviewMetadataDeltaEventSchema = z
	.object({
		...bridgeProductReviewMetadataIdentityShape,
		contentSources: z
			.array(bridgeProductReviewContentSourceDescriptorSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
			.readonly(),
		eventKind: z.literal('review.delta'),
		fromRevision: bridgeProductNonnegativeSequenceSchema,
		operations: z
			.array(bridgeProductReviewMetadataOperationSchema)
			.max(BRIDGE_PRODUCT_MAXIMUM_REVIEW_METADATA_WINDOW_ENTRY_COUNT)
			.readonly(),
		summary: bridgeProductReviewPackageSummarySchema,
		toRevision: bridgeProductNonnegativeSequenceSchema,
	})
	.strict()
	.superRefine((event, context): void => {
		if (event.revision !== event.toRevision || event.fromRevision > event.toRevision) {
			context.addIssue({
				code: 'custom',
				message: 'Review metadata delta revision lineage is invalid.',
				path: ['toRevision'],
			});
		}
	});

export const bridgeProductReviewMetadataInvalidatedEventSchema = z
	.object({
		...bridgeProductReviewMetadataIdentityShape,
		eventKind: z.literal('review.invalidated'),
		itemIds: z.array(bridgeProductIdentifierSchema).readonly(),
		pathHints: z.array(bridgeProductDisplayPathSchema).readonly(),
		reason: z.enum(['sourceChanged', 'watchEvent', 'lineageReplaced', 'unknown']),
		scope: z.enum(['package', 'items', 'paths', 'treeWindow']),
	})
	.strict();

export const bridgeProductReviewMetadataResetEventSchema = z
	.object({
		...bridgeProductReviewMetadataIdentityShape,
		eventKind: z.literal('review.reset'),
		reason: z.enum(['sourceChanged', 'subscriptionReset', 'providerRestart', 'authorityChanged']),
	})
	.strict();

export const bridgeProductReviewMetadataEventSchema = z
	.discriminatedUnion('eventKind', [
		bridgeProductReviewSourceAcceptedEventSchema,
		bridgeProductReviewMetadataSnapshotEventSchema,
		bridgeProductReviewMetadataWindowEventSchema,
		bridgeProductReviewMetadataDeltaEventSchema,
		bridgeProductReviewMetadataInvalidatedEventSchema,
		bridgeProductReviewMetadataResetEventSchema,
	])
	.superRefine((event, context): void => {
		if (!('contentSources' in event)) return;
		for (const [sourceIndex, source] of event.contentSources.entries()) {
			if (
				source.packageId !== event.packageId ||
				source.reviewGeneration !== event.generation ||
				source.sourceIdentity !== event.sourceIdentity
			) {
				context.addIssue({
					code: 'custom',
					message: 'Review content source identity does not match its metadata event.',
					path: ['contentSources', sourceIndex],
				});
			}
		}
	});

export type BridgeProductReviewMetadataEvent = z.infer<
	typeof bridgeProductReviewMetadataEventSchema
>;
export type BridgeProductReviewExtentFact = z.infer<typeof bridgeProductReviewExtentFactSchema>;
export type BridgeProductReviewItemMetadata = z.infer<typeof bridgeProductReviewItemMetadataSchema>;
export type BridgeProductReviewTreeRow = z.infer<typeof bridgeProductReviewTreeRowSchema>;

function validateOrderedReviewWindow(props: {
	readonly context: z.RefinementCtx;
	readonly count: number;
	readonly countPath: readonly string[];
	readonly finalWindow: boolean;
	readonly startIndex: number;
	readonly totalCount: number;
	readonly totalCountPath: readonly string[];
}): void {
	const endIndex = props.startIndex + props.count;
	if (!Number.isSafeInteger(endIndex) || endIndex > props.totalCount) {
		props.context.addIssue({
			code: 'custom',
			message: 'Review metadata window exceeds its declared ordered total.',
			path: [...props.totalCountPath],
		});
		return;
	}
	if (props.finalWindow !== (endIndex === props.totalCount)) {
		props.context.addIssue({
			code: 'custom',
			message: 'Review metadata final-window state does not match its ordered extent.',
			path: ['finalWindow'],
		});
	}
}

function validateReviewMetadataWindowPayload(
	event: {
		readonly itemMetadata: readonly unknown[];
		readonly itemWindow: { readonly itemCount: number };
		readonly treeRows: readonly unknown[];
		readonly treeWindow: { readonly rowCount: number };
	},
	context: z.RefinementCtx,
): void {
	if (event.itemWindow.itemCount !== event.itemMetadata.length) {
		context.addIssue({
			code: 'custom',
			message: 'Review item-window count does not match the carried item metadata.',
			path: ['itemWindow', 'itemCount'],
		});
	}
	if (event.treeWindow.rowCount !== event.treeRows.length) {
		context.addIssue({
			code: 'custom',
			message: 'Review tree-window count does not match the carried tree rows.',
			path: ['treeWindow', 'rowCount'],
		});
	}
}
