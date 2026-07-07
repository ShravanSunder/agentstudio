import { z } from 'zod';

import { parseBridgeResourceUrl } from '../../bridge/bridge-resource-url.js';
import { worktreeFileVirtualizedExtentKindSchema } from '../../features/worktree-file/models/worktree-file-protocol-models.js';
import {
	bridgeContentRoleSchema,
	bridgeFileChangeKindSchema,
	bridgeReviewContentLineCountsByRoleSchema,
} from '../../foundation/review-package/bridge-review-package-schema.js';
import { bridgeTelemetryScopeSchema } from '../../foundation/telemetry/bridge-telemetry-scope.js';
import {
	bridgeWorkerDemandRankSchema,
	bridgeWorkerPierreRenderBudgetSchema,
	bridgeWorkerPierreRenderJobSchema,
} from './bridge-worker-pierre-render-job.js';

export const BRIDGE_WORKER_WIRE_VERSION = 1 as const;

const bridgeWorkerRequestIdSchema = z.string().min(1);
const bridgeWorkerEpochSchema = z.number().int().nonnegative();
const bridgeWorkerSequenceSchema = z.number().int().nonnegative();
const bridgeWorkerIssuedAtMillisecondsSchema = z.number().finite().nonnegative();

export const bridgeWorkerTransferDescriptorSchema = z
	.object({
		messageKind: z.string().min(1),
		fieldPath: z.array(z.string().min(1)).readonly(),
		byteLength: z.number().int().nonnegative(),
		mode: z.enum(['transfer', 'clone']),
	})
	.strict();

export type BridgeWorkerTransferDescriptor = z.infer<typeof bridgeWorkerTransferDescriptorSchema>;

const bridgeWorkerMainToServerBaseSchema = z
	.object({
		wireVersion: z.literal(BRIDGE_WORKER_WIRE_VERSION),
		direction: z.literal('mainToServerWorker'),
		kind: z.literal('command'),
		requestId: bridgeWorkerRequestIdSchema,
		epoch: bridgeWorkerEpochSchema,
		issuedAtMilliseconds: bridgeWorkerIssuedAtMillisecondsSchema.optional(),
		transferDescriptors: z.array(bridgeWorkerTransferDescriptorSchema).readonly(),
	})
	.strict();

export const bridgeWorkerSelectCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('select'),
		selectedItemId: z.string().min(1),
		selectedSource: z.enum(['user', 'keyboard', 'programmatic']),
	})
	.strict();

export const bridgeWorkerViewportCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('viewport'),
		visibleItemIds: z.array(z.string().min(1)).readonly(),
		firstVisibleIndex: z.number().int().nonnegative(),
		lastVisibleIndex: z.number().int().nonnegative(),
		phase: z.enum(['momentum', 'settled']),
	})
	.strict();

export const bridgeWorkerHoverCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('hover'),
		hoveredItemId: z.string().min(1).nullable(),
	})
	.strict();

export const bridgeWorkerMarkFileViewedCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('markFileViewed'),
		filePathHash: z.string().min(1),
		viewedAtSequence: bridgeWorkerSequenceSchema,
	})
	.strict();

export const bridgeWorkerModeCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('mode'),
		mode: z.enum(['review', 'fileView']),
	})
	.strict();

export const bridgeWorkerReviewInvalidateCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('reviewInvalidate'),
		scope: z.enum(['package', 'items', 'paths', 'treeWindow']),
		itemIds: z.array(z.string().min(1)).readonly(),
		pathHints: z.array(z.string().min(1)).readonly(),
		reason: z.enum(['sourceChanged', 'watchEvent', 'lineageReplaced', 'unknown']),
	})
	.strict();

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
		availableContentRoles: z.array(bridgeContentRoleSchema).readonly(),
		contentLineCountsByRole: bridgeReviewContentLineCountsByRoleSchema,
	})
	.strict();

export const bridgeWorkerReviewContentRequestDescriptorSchema = z
	.object({
		itemId: z.string().min(1),
		role: bridgeContentRoleSchema,
		handleId: z.string().min(1),
		reviewGeneration: z.number().int().nonnegative(),
		resourceUrl: z.string().min(1),
		contentHash: z.string().min(1),
		contentHashAlgorithm: z.string().min(1),
		language: z.string().nullable(),
		sizeBytes: z.number().int().nonnegative(),
		isBinary: z.boolean(),
	})
	.strict();

export const bridgeWorkerReviewRenderSemanticsSchema = z
	.object({
		itemId: z.string().min(1),
		itemKind: z.enum(['file', 'diff']),
		changeKind: bridgeFileChangeKindSchema,
		displayPath: z.string().min(1),
		basePath: z.string().min(1).nullable(),
		headPath: z.string().min(1).nullable(),
		language: z.string().nullable(),
		contentLineCountsByRole: bridgeReviewContentLineCountsByRoleSchema,
	})
	.strict();

export const bridgeWorkerFileViewContentMetadataSchema = z
	.object({
		itemId: z.string().min(1),
		path: z.string().min(1),
		language: z.string().nullable(),
		cacheKey: z.string().min(1),
		sizeBytes: z.number().int().nonnegative(),
		contentHandle: z.string().min(1),
		descriptorId: z.string().min(1),
		contentHash: z.string().min(1).optional(),
		virtualizedExtentKind: worktreeFileVirtualizedExtentKindSchema,
		lineCount: z.number().int().nonnegative().optional(),
		isBinary: z.boolean(),
		canFetchContent: z.boolean(),
	})
	.strict();

const bridgeWorkerFileViewContentRequestDescriptorBaseSchema = z
	.object({
		itemId: z.string().min(1),
		path: z.string().min(1),
		handleId: z.string().min(1),
		descriptorId: z.string().min(1),
		resourceKind: z.literal('worktree.fileContent'),
		resourceUrl: z.string().min(1),
		contentHash: z.string().min(1).optional(),
		contentHashAlgorithm: z.string().min(1).optional(),
		language: z.string().nullable(),
		sizeBytes: z.number().int().nonnegative(),
		maxBytes: z.number().int().positive(),
		isBinary: z.boolean(),
	})
	.strict();

type BridgeWorkerFileViewContentRequestDescriptorDraft = z.infer<
	typeof bridgeWorkerFileViewContentRequestDescriptorBaseSchema
>;

export const bridgeWorkerFileViewContentRequestDescriptorSchema =
	bridgeWorkerFileViewContentRequestDescriptorBaseSchema.superRefine(
		validateBridgeWorkerFileViewContentRequestDescriptor,
	);

export const bridgeCommWorkerRowSchema = z
	.object({
		id: z.string().min(1),
		parentId: z.string().min(1).nullable(),
		index: z.number().int().nonnegative(),
	})
	.strict();

export const bridgeWorkerReviewSourceUpdateCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('reviewSourceUpdate'),
		contentItems: z.array(bridgeWorkerReviewContentMetadataSchema).readonly(),
		contentRequestDescriptors: z.array(bridgeWorkerReviewContentRequestDescriptorSchema).readonly(),
		renderSemantics: z.array(bridgeWorkerReviewRenderSemanticsSchema).readonly(),
		rows: z.array(bridgeCommWorkerRowSchema).readonly(),
	})
	.strict();

const bridgeWorkerFileViewSourceUpdateCommandBaseSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('fileViewSourceUpdate'),
		contentItems: z.array(bridgeWorkerFileViewContentMetadataSchema).readonly(),
		contentRequestDescriptors: z
			.array(bridgeWorkerFileViewContentRequestDescriptorSchema)
			.readonly(),
		rows: z.array(bridgeCommWorkerRowSchema).readonly(),
	})
	.strict();

type BridgeWorkerFileViewSourceUpdateCommandDraft = z.infer<
	typeof bridgeWorkerFileViewSourceUpdateCommandBaseSchema
>;

export const bridgeWorkerFileViewSourceUpdateCommandSchema =
	bridgeWorkerFileViewSourceUpdateCommandBaseSchema.superRefine(
		validateBridgeWorkerFileViewSourceUpdateCommand,
	);

const bridgeWorkerMainToServerCommandBaseSchema = z.discriminatedUnion('command', [
	bridgeWorkerSelectCommandSchema,
	bridgeWorkerViewportCommandSchema,
	bridgeWorkerHoverCommandSchema,
	bridgeWorkerMarkFileViewedCommandSchema,
	bridgeWorkerModeCommandSchema,
	bridgeWorkerReviewInvalidateCommandSchema,
	bridgeWorkerReviewSourceUpdateCommandSchema,
	bridgeWorkerFileViewSourceUpdateCommandBaseSchema,
]);

export const bridgeWorkerMainToServerCommandSchema =
	bridgeWorkerMainToServerCommandBaseSchema.superRefine((command, context) => {
		if (command.command === 'fileViewSourceUpdate') {
			validateBridgeWorkerFileViewSourceUpdateCommand(command, context);
		}
	});

export const bridgeWorkerMainToServerMessageSchema = bridgeWorkerMainToServerCommandSchema;

function validateBridgeWorkerFileViewSourceUpdateCommand(
	command: BridgeWorkerFileViewSourceUpdateCommandDraft,
	context: z.RefinementCtx,
): void {
	const metadataByItemId = new Map(
		command.contentItems.map((contentItem) => [contentItem.itemId, contentItem]),
	);
	const descriptorsByItemId = new Map<
		string,
		BridgeWorkerFileViewSourceUpdateCommandDraft['contentRequestDescriptors']
	>();
	for (const descriptor of command.contentRequestDescriptors) {
		descriptorsByItemId.set(descriptor.itemId, [
			...(descriptorsByItemId.get(descriptor.itemId) ?? []),
			descriptor,
		]);
		if (!metadataByItemId.has(descriptor.itemId)) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: `File View descriptor ${descriptor.itemId} has no matching metadata item.`,
				path: ['contentRequestDescriptors'],
			});
		}
	}
	for (const contentItem of command.contentItems) {
		const descriptors = descriptorsByItemId.get(contentItem.itemId) ?? [];
		if (contentItem.canFetchContent && descriptors.length !== 1) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: `Fetchable File View item ${contentItem.itemId} must have exactly one request descriptor.`,
				path: ['contentRequestDescriptors'],
			});
			continue;
		}
		if (!contentItem.canFetchContent && descriptors.length !== 0) {
			context.addIssue({
				code: z.ZodIssueCode.custom,
				message: `Non-fetchable File View item ${contentItem.itemId} must not have request descriptors.`,
				path: ['contentRequestDescriptors'],
			});
			continue;
		}
		const descriptor = descriptors[0];
		if (descriptor === undefined) {
			continue;
		}
		validateBridgeWorkerFileViewDescriptorMatchesMetadata({
			contentItem,
			context,
			descriptor,
		});
	}
}

function validateBridgeWorkerFileViewDescriptorMatchesMetadata(props: {
	readonly contentItem: BridgeWorkerFileViewSourceUpdateCommandDraft['contentItems'][number];
	readonly context: z.RefinementCtx;
	readonly descriptor: BridgeWorkerFileViewSourceUpdateCommandDraft['contentRequestDescriptors'][number];
}): void {
	const mismatchedFields = [
		props.descriptor.path === props.contentItem.path ? null : 'path',
		props.descriptor.handleId === props.contentItem.contentHandle ? null : 'handleId',
		props.descriptor.descriptorId === props.contentItem.descriptorId ? null : 'descriptorId',
		parseBridgeWorkerFileViewContentResourceDescriptorId(props.descriptor.resourceUrl) ===
		props.descriptor.descriptorId
			? null
			: 'resourceUrl',
		props.descriptor.contentHash === props.contentItem.contentHash ? null : 'contentHash',
		props.descriptor.language === props.contentItem.language ? null : 'language',
		props.descriptor.sizeBytes === props.contentItem.sizeBytes ? null : 'sizeBytes',
		props.descriptor.isBinary === props.contentItem.isBinary ? null : 'isBinary',
	].filter((fieldName): fieldName is string => fieldName !== null);
	if (mismatchedFields.length === 0) {
		return;
	}
	props.context.addIssue({
		code: z.ZodIssueCode.custom,
		message: `File View descriptor ${props.descriptor.itemId} does not match metadata fields: ${mismatchedFields.join(', ')}.`,
		path: ['contentRequestDescriptors'],
	});
}

function validateBridgeWorkerFileViewContentRequestDescriptor(
	descriptor: BridgeWorkerFileViewContentRequestDescriptorDraft,
	context: z.RefinementCtx,
): void {
	const parsedResourceUrl = parseBridgeWorkerFileViewContentResourceUrl(descriptor.resourceUrl);
	const mismatchedFields = [
		parsedResourceUrl === null ? 'resourceUrl' : null,
		parsedResourceUrl !== null && parsedResourceUrl.resourceKind !== descriptor.resourceKind
			? 'resourceKind'
			: null,
		parsedResourceUrl !== null && parsedResourceUrl.resourceId !== descriptor.descriptorId
			? 'descriptorId'
			: null,
		parsedResourceUrl !== null && parsedResourceUrl.canonicalUrl !== descriptor.resourceUrl
			? 'resourceUrl'
			: null,
	].filter((fieldName): fieldName is string => fieldName !== null);
	if (mismatchedFields.length === 0) {
		return;
	}
	context.addIssue({
		code: z.ZodIssueCode.custom,
		message: `File View content request descriptor ${descriptor.itemId} must use a canonical worktree.fileContent resource URL matching its descriptor id: ${[...new Set(mismatchedFields)].join(', ')}.`,
		path: ['resourceUrl'],
	});
}

function parseBridgeWorkerFileViewContentResourceDescriptorId(resourceUrl: string): string | null {
	return parseBridgeWorkerFileViewContentResourceUrl(resourceUrl)?.resourceId ?? null;
}

function parseBridgeWorkerFileViewContentResourceUrl(resourceUrl: string): {
	readonly resourceKind: 'worktree.fileContent';
	readonly resourceId: string;
	readonly canonicalUrl: string;
} | null {
	const parsedResourceUrl = parseBridgeResourceUrl(resourceUrl);
	if (
		parsedResourceUrl?.kind !== 'worktreeResource' ||
		parsedResourceUrl.resourceKind !== 'worktree.fileContent'
	) {
		return null;
	}
	return {
		resourceKind: parsedResourceUrl.resourceKind,
		resourceId: parsedResourceUrl.resourceId,
		canonicalUrl: parsedResourceUrl.canonicalUrl,
	};
}

export type BridgeWorkerSelectCommand = z.infer<typeof bridgeWorkerSelectCommandSchema>;
export type BridgeWorkerViewportCommand = z.infer<typeof bridgeWorkerViewportCommandSchema>;
export type BridgeWorkerHoverCommand = z.infer<typeof bridgeWorkerHoverCommandSchema>;
export type BridgeWorkerMarkFileViewedCommand = z.infer<
	typeof bridgeWorkerMarkFileViewedCommandSchema
>;
export type BridgeWorkerModeCommand = z.infer<typeof bridgeWorkerModeCommandSchema>;
export type BridgeWorkerReviewInvalidateCommand = z.infer<
	typeof bridgeWorkerReviewInvalidateCommandSchema
>;
export type BridgeWorkerReviewSourceUpdateCommand = z.infer<
	typeof bridgeWorkerReviewSourceUpdateCommandSchema
>;
export type BridgeWorkerFileViewSourceUpdateCommand = z.infer<
	typeof bridgeWorkerFileViewSourceUpdateCommandSchema
>;
export type BridgeWorkerMainToServerCommand = z.infer<typeof bridgeWorkerMainToServerCommandSchema>;
export type BridgeWorkerMainToServerMessage = BridgeWorkerMainToServerCommand;

export const bridgeCommWorkerTelemetryBootstrapConfigSchema = z
	.object({
		enabledScopes: z.array(bridgeTelemetryScopeSchema).readonly(),
		endpointUrl: z.string().min(1),
		maxSamplesPerBatch: z.number().int().positive(),
		maxEncodedBatchBytes: z.number().int().positive(),
		minimumFlushIntervalMilliseconds: z.number().int().nonnegative(),
		scenario: z.string().min(1),
	})
	.strict();

export type BridgeCommWorkerTelemetryBootstrapConfig = z.infer<
	typeof bridgeCommWorkerTelemetryBootstrapConfigSchema
>;

export const bridgeCommWorkerBootstrapRequestSchema = z
	.object({
		schemaVersion: z.literal(BRIDGE_WORKER_WIRE_VERSION),
		method: z.literal('bridgeCommWorker.bootstrap'),
		requestId: bridgeWorkerRequestIdSchema,
		runtime: z
			.object({
				bridgeDemandRank: bridgeWorkerDemandRankSchema,
				budget: bridgeWorkerPierreRenderBudgetSchema,
				contentItems: z.array(bridgeWorkerReviewContentMetadataSchema).readonly(),
				contentRequestDescriptors: z
					.array(bridgeWorkerReviewContentRequestDescriptorSchema)
					.readonly(),
				renderSemantics: z.array(bridgeWorkerReviewRenderSemanticsSchema).readonly(),
				rows: z.array(bridgeCommWorkerRowSchema).readonly(),
				maxPreparationSliceMs: z.number().finite().positive().optional(),
				telemetryConfig: bridgeCommWorkerTelemetryBootstrapConfigSchema.optional(),
			})
			.strict(),
	})
	.strict();

export const bridgeWorkerPanelChromePatchPayloadSchema = z
	.object({
		isLoading: z.boolean().optional(),
		message: z.string().min(1).nullable().optional(),
	})
	.strict();

const bridgeWorkerSelectionPatchSchema = z.discriminatedUnion('operation', [
	z
		.object({
			slice: z.literal('selection'),
			operation: z.literal('upsert'),
			payload: bridgeWorkerSelectionPatchPayloadSchema,
		})
		.strict(),
	z
		.object({
			slice: z.literal('selection'),
			operation: z.literal('reset'),
		})
		.strict(),
	z
		.object({
			slice: z.literal('selection'),
			operation: z.literal('delete'),
		})
		.strict(),
]);

const bridgeWorkerViewportPatchSchema = z.discriminatedUnion('operation', [
	z
		.object({
			slice: z.literal('viewport'),
			operation: z.literal('upsert'),
			payload: bridgeWorkerViewportPatchPayloadSchema,
		})
		.strict(),
	z
		.object({
			slice: z.literal('viewport'),
			operation: z.literal('reset'),
		})
		.strict(),
	z
		.object({
			slice: z.literal('viewport'),
			operation: z.literal('delete'),
		})
		.strict(),
]);

const bridgeWorkerRowPaintPatchSchema = z.discriminatedUnion('operation', [
	z
		.object({
			slice: z.literal('rowPaint'),
			operation: z.literal('upsert'),
			itemId: z.string().min(1),
			payload: bridgeWorkerRowPaintPatchPayloadSchema,
		})
		.strict(),
	z
		.object({
			slice: z.literal('rowPaint'),
			operation: z.literal('delete'),
			itemId: z.string().min(1),
		})
		.strict(),
	z
		.object({
			slice: z.literal('rowPaint'),
			operation: z.literal('reset'),
		})
		.strict(),
]);

const bridgeWorkerContentAvailabilityPatchSchema = z.discriminatedUnion('operation', [
	z
		.object({
			slice: z.literal('contentAvailability'),
			operation: z.literal('upsert'),
			itemId: z.string().min(1),
			payload: bridgeWorkerContentAvailabilityPatchPayloadSchema,
		})
		.strict(),
	z
		.object({
			slice: z.literal('contentAvailability'),
			operation: z.literal('delete'),
			itemId: z.string().min(1),
		})
		.strict(),
	z
		.object({
			slice: z.literal('contentAvailability'),
			operation: z.literal('reset'),
		})
		.strict(),
]);

const bridgeWorkerPanelChromePatchSchema = z.discriminatedUnion('operation', [
	z
		.object({
			slice: z.literal('panelChrome'),
			operation: z.literal('upsert'),
			payload: bridgeWorkerPanelChromePatchPayloadSchema,
		})
		.strict(),
	z
		.object({
			slice: z.literal('panelChrome'),
			operation: z.literal('reset'),
		})
		.strict(),
	z
		.object({
			slice: z.literal('panelChrome'),
			operation: z.literal('delete'),
		})
		.strict(),
]);

export const bridgeWorkerSlicePatchSchema = z.discriminatedUnion('slice', [
	bridgeWorkerSelectionPatchSchema,
	bridgeWorkerViewportPatchSchema,
	bridgeWorkerRowPaintPatchSchema,
	bridgeWorkerContentAvailabilityPatchSchema,
	bridgeWorkerPanelChromePatchSchema,
]);

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
export type BridgeWorkerFileViewContentRequestDescriptor = z.infer<
	typeof bridgeWorkerFileViewContentRequestDescriptorSchema
>;
export type BridgeWorkerContentMetadata =
	| BridgeWorkerFileViewContentMetadata
	| BridgeWorkerReviewContentMetadata;
export type BridgeCommWorkerBootstrapRow = z.infer<typeof bridgeCommWorkerRowSchema>;
export type BridgeCommWorkerBootstrapRequest = z.infer<
	typeof bridgeCommWorkerBootstrapRequestSchema
>;
export type BridgeWorkerPanelChromePatchPayload = z.infer<
	typeof bridgeWorkerPanelChromePatchPayloadSchema
>;
export type BridgeWorkerSlicePatch = z.infer<typeof bridgeWorkerSlicePatchSchema>;

const bridgeWorkerServerToMainBaseSchema = z
	.object({
		wireVersion: z.literal(BRIDGE_WORKER_WIRE_VERSION),
		direction: z.literal('serverWorkerToMain'),
		transferDescriptors: z.array(bridgeWorkerTransferDescriptorSchema).readonly(),
	})
	.strict();

export const bridgeWorkerHealthEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		kind: z.literal('health'),
		requestId: bridgeWorkerRequestIdSchema.optional(),
		status: z.enum(['ready', 'degraded']),
		message: z.string().min(1).optional(),
	})
	.strict();

export const bridgeWorkerSlicePatchEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		kind: z.literal('slicePatch'),
		epoch: bridgeWorkerEpochSchema,
		sequence: bridgeWorkerSequenceSchema,
		patches: z.array(bridgeWorkerSlicePatchSchema).readonly(),
	})
	.strict();

export const bridgeWorkerSubscriptionEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		kind: z.literal('subscription'),
		requestId: bridgeWorkerRequestIdSchema,
		subscription: z.enum(['reviewContent', 'fileViewContent', 'telemetry']),
		status: z.enum(['subscribed', 'unsubscribed', 'rejected']),
	})
	.strict();

export const bridgeWorkerPierreRenderJobEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		kind: z.literal('pierreRenderJob'),
		job: bridgeWorkerPierreRenderJobSchema,
	})
	.strict();

export const bridgeWorkerServerToMainMessageSchema = z.discriminatedUnion('kind', [
	bridgeWorkerHealthEventSchema,
	bridgeWorkerSlicePatchEventSchema,
	bridgeWorkerSubscriptionEventSchema,
	bridgeWorkerPierreRenderJobEventSchema,
]);

export type BridgeWorkerHealthEvent = z.infer<typeof bridgeWorkerHealthEventSchema>;
export type BridgeWorkerSlicePatchEvent = z.infer<typeof bridgeWorkerSlicePatchEventSchema>;
export type BridgeWorkerSubscriptionEvent = z.infer<typeof bridgeWorkerSubscriptionEventSchema>;
export type BridgeWorkerPierreRenderJobEvent = z.infer<
	typeof bridgeWorkerPierreRenderJobEventSchema
>;
export type BridgeWorkerServerToMainMessage = z.infer<typeof bridgeWorkerServerToMainMessageSchema>;

export function parseBridgeWorkerMainToServerMessage(
	value: unknown,
): BridgeWorkerMainToServerMessage {
	return bridgeWorkerMainToServerMessageSchema.parse(value);
}

export function parseBridgeWorkerServerToMainMessage(
	value: unknown,
): BridgeWorkerServerToMainMessage {
	return bridgeWorkerServerToMainMessageSchema.parse(value);
}

export function parseBridgeCommWorkerBootstrapRequest(
	value: unknown,
): BridgeCommWorkerBootstrapRequest {
	return bridgeCommWorkerBootstrapRequestSchema.parse(value);
}
