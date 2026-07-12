import { z } from 'zod';

import {
	bridgeActiveViewerModeUpdateSchema,
	bridgeIntakeReadyParamsSchema,
} from '../../bridge/bridge-rpc-client.js';
import { bridgeTelemetryScopeSchema } from '../../foundation/telemetry/bridge-telemetry-scope.js';
import { bridgeDemandLaneSchema } from '../models/bridge-demand-models.js';
import {
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductSurfaceSchema,
	type BridgeProductSurface,
} from './bridge-product-contract-primitives.js';
import {
	bridgeProductReviewContentLineCountsByRoleSchema,
	bridgeProductReviewContentRoleSchema,
	bridgeProductReviewFileChangeKindSchema,
} from './bridge-product-review-primitives.js';
import {
	bridgeProductFileTruncationKindSchema,
	bridgeProductFileVirtualizedExtentKindSchema,
} from './bridge-product-subscription-contracts.js';
import {
	BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT,
	bridgeWorkerFileDisplayPatchSchema,
} from './bridge-worker-file-display-patch-contracts.js';
import { bridgeWorkerFileQuerySchema } from './bridge-worker-file-query-contracts.js';
import {
	bridgeWorkerDemandRankSchema,
	bridgeWorkerPierreRenderBudgetSchema,
	bridgeWorkerPierreRenderJobSchema,
} from './bridge-worker-pierre-render-job.js';

export const BRIDGE_WORKER_WIRE_VERSION = 1 as const;
export {
	BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT,
	bridgeWorkerFileDisplayPatchSchema,
} from './bridge-worker-file-display-patch-contracts.js';
export type { BridgeWorkerFileDisplayPatch } from './bridge-worker-file-display-patch-contracts.js';

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
		fileId: z.string().min(1),
	})
	.strict();

export const bridgeWorkerMetadataInterestRequestSchema = z
	.object({
		protocol: z.literal('review'),
		streamId: z.string().min(1).optional(),
		generation: z.number().int().nonnegative().optional(),
		itemIds: z.array(z.string().min(1)).readonly().optional(),
		paths: z.array(z.string().min(1)).readonly().optional(),
		lane: bridgeDemandLaneSchema,
		loaded_by: z.enum(['foreground', 'visible', 'nearby', 'speculative', 'idle']).optional(),
	})
	.strict();

export const bridgeWorkerMetadataInterestUpdateCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('metadataInterestUpdate'),
		request: bridgeWorkerMetadataInterestRequestSchema,
	})
	.strict();

const bridgeWorkerReviewIntakeReadyParamsSchema = bridgeIntakeReadyParamsSchema
	.extend({
		protocolId: z.literal('review'),
	})
	.strict();

export const bridgeWorkerReviewIntakeReadyCommandSchema = bridgeWorkerMainToServerBaseSchema
	.merge(bridgeWorkerReviewIntakeReadyParamsSchema)
	.extend({
		command: z.literal('reviewIntakeReady'),
	})
	.strict();

export const bridgeWorkerActiveViewerModeUpdateCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('activeViewerModeUpdate'),
		update: bridgeActiveViewerModeUpdateSchema,
	})
	.strict();

export const bridgeWorkerModeCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('mode'),
		mode: z.enum(['review', 'fileView']),
	})
	.strict();

export const bridgeWorkerFileQueryUpdateCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('fileQueryUpdate'),
		query: bridgeWorkerFileQuerySchema,
	})
	.strict();

export const bridgeWorkerFileDisplayResyncReasonSchema = z.enum([
	'acknowledgementMismatch',
	'acknowledgementTimeout',
	'bufferOverflow',
	'protocolViolation',
]);

export const bridgeWorkerFileDisplayResyncCommandSchema = bridgeWorkerMainToServerBaseSchema
	.extend({
		command: z.literal('fileDisplayResync'),
		reason: bridgeWorkerFileDisplayResyncReasonSchema,
		transactionId: bridgeProductIdentifierSchema.nullable(),
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

const bridgeWorkerReviewContentRequestDescriptorBaseSchema = z
	.object({
		itemId: z.string().min(1),
		role: bridgeProductReviewContentRoleSchema,
		handleId: z.string().min(1),
		reviewGeneration: z.number().int().nonnegative(),
		resourceUrl: z.string().min(1),
		contentHash: z.string().min(1),
		contentHashAlgorithm: z.string().min(1),
		language: z.string().nullable(),
		sizeBytes: z.number().int().nonnegative(),
		expectedBytes: z.number().int().nonnegative().optional(),
		maxBytes: z.number().int().positive(),
		isBinary: z.boolean(),
	})
	.strict();

type BridgeWorkerReviewContentRequestDescriptorDraft = z.infer<
	typeof bridgeWorkerReviewContentRequestDescriptorBaseSchema
>;

export const bridgeWorkerReviewContentRequestDescriptorSchema =
	bridgeWorkerReviewContentRequestDescriptorBaseSchema.superRefine(
		validateBridgeWorkerReviewContentRequestDescriptor,
	);

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

export const bridgeWorkerMainToServerCommandSchema = z.discriminatedUnion('command', [
	bridgeWorkerSelectCommandSchema,
	bridgeWorkerViewportCommandSchema,
	bridgeWorkerHoverCommandSchema,
	bridgeWorkerMarkFileViewedCommandSchema,
	bridgeWorkerMetadataInterestUpdateCommandSchema,
	bridgeWorkerReviewIntakeReadyCommandSchema,
	bridgeWorkerActiveViewerModeUpdateCommandSchema,
	bridgeWorkerModeCommandSchema,
	bridgeWorkerReviewInvalidateCommandSchema,
	bridgeWorkerReviewSourceUpdateCommandSchema,
	bridgeWorkerFileQueryUpdateCommandSchema,
	bridgeWorkerFileDisplayResyncCommandSchema,
]);

export const bridgeWorkerMainToServerMessageSchema = bridgeWorkerMainToServerCommandSchema;

function validateBridgeWorkerReviewContentRequestDescriptor(
	descriptor: BridgeWorkerReviewContentRequestDescriptorDraft,
	context: z.RefinementCtx,
): void {
	if (descriptor.expectedBytes !== undefined && descriptor.expectedBytes !== descriptor.sizeBytes) {
		context.addIssue({
			code: z.ZodIssueCode.custom,
			message: `Review content request descriptor ${descriptor.itemId} expectedBytes must match sizeBytes when present.`,
			path: ['expectedBytes'],
		});
	}
	if (
		descriptor.expectedBytes !== undefined &&
		descriptor.maxBytes < Math.max(descriptor.expectedBytes, 1)
	) {
		context.addIssue({
			code: z.ZodIssueCode.custom,
			message: `Review content request descriptor ${descriptor.itemId} maxBytes must cover expectedBytes.`,
			path: ['maxBytes'],
		});
	}
}

export type BridgeWorkerSelectCommand = z.infer<typeof bridgeWorkerSelectCommandSchema>;
export type BridgeWorkerViewportCommand = z.infer<typeof bridgeWorkerViewportCommandSchema>;
export type BridgeWorkerHoverCommand = z.infer<typeof bridgeWorkerHoverCommandSchema>;
export type BridgeWorkerMarkFileViewedCommand = z.infer<
	typeof bridgeWorkerMarkFileViewedCommandSchema
>;
export type BridgeWorkerMetadataInterestRequest = z.infer<
	typeof bridgeWorkerMetadataInterestRequestSchema
>;
export type BridgeWorkerMetadataInterestUpdateCommand = z.infer<
	typeof bridgeWorkerMetadataInterestUpdateCommandSchema
>;
export type BridgeWorkerReviewIntakeReadyCommand = z.infer<
	typeof bridgeWorkerReviewIntakeReadyCommandSchema
>;
export type BridgeWorkerActiveViewerModeUpdateCommand = z.infer<
	typeof bridgeWorkerActiveViewerModeUpdateCommandSchema
>;
export type BridgeWorkerModeCommand = z.infer<typeof bridgeWorkerModeCommandSchema>;
export type BridgeWorkerReviewInvalidateCommand = z.infer<
	typeof bridgeWorkerReviewInvalidateCommandSchema
>;
export type BridgeWorkerReviewSourceUpdateCommand = z.infer<
	typeof bridgeWorkerReviewSourceUpdateCommandSchema
>;
export type BridgeWorkerFileQueryUpdateCommand = z.infer<
	typeof bridgeWorkerFileQueryUpdateCommandSchema
>;
export type BridgeWorkerFileDisplayResyncReason = z.infer<
	typeof bridgeWorkerFileDisplayResyncReasonSchema
>;
export type BridgeWorkerFileDisplayResyncCommand = z.infer<
	typeof bridgeWorkerFileDisplayResyncCommandSchema
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
				surfacePolicies: z
					.object({
						fileView: z
							.object({
								bridgeDemandRank: bridgeWorkerDemandRankSchema,
								budget: bridgeWorkerPierreRenderBudgetSchema,
							})
							.strict(),
						review: z
							.object({
								bridgeDemandRank: bridgeWorkerDemandRankSchema,
								budget: bridgeWorkerPierreRenderBudgetSchema,
							})
							.strict(),
					})
					.strict()
					.optional(),
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
export type BridgeWorkerContentMetadata =
	| BridgeWorkerFileViewContentMetadata
	| BridgeWorkerReviewContentMetadata;

export function isBridgeWorkerFileViewContentMetadata(
	metadata: BridgeWorkerContentMetadata | null,
): metadata is BridgeWorkerFileViewContentMetadata {
	return metadata !== null && bridgeWorkerFileViewContentMetadataSchema.safeParse(metadata).success;
}
export type BridgeCommWorkerBootstrapRow = z.infer<typeof bridgeCommWorkerRowSchema>;
export type BridgeCommWorkerBootstrapRequest = z.infer<
	typeof bridgeCommWorkerBootstrapRequestSchema
>;
export type BridgeWorkerPanelChromePatchPayload = z.infer<
	typeof bridgeWorkerPanelChromePatchPayloadSchema
>;
export type BridgeWorkerSlicePatch = z.infer<typeof bridgeWorkerSlicePatchSchema>;
export type BridgeWorkerSurfacePublicationEnvelope<
	TSurface extends BridgeProductSurface,
	TPublication extends Readonly<Record<string, unknown>>,
> = Readonly<{
	publicationSequence: number;
	surface: TSurface;
	workerDerivationEpoch: number;
}> &
	TPublication;

const bridgeWorkerServerToMainBaseSchema = z
	.object({
		wireVersion: z.literal(BRIDGE_WORKER_WIRE_VERSION),
		direction: z.literal('serverWorkerToMain'),
		transferDescriptors: z.array(bridgeWorkerTransferDescriptorSchema).readonly(),
	})
	.strict();

const bridgeWorkerSurfacePublicationEnvelopeShape = {
	publicationSequence: bridgeWorkerSequenceSchema,
	surface: bridgeProductSurfaceSchema,
	workerDerivationEpoch: bridgeWorkerEpochSchema,
} as const;

export const bridgeWorkerHealthEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		kind: z.literal('health'),
		requestId: bridgeWorkerRequestIdSchema.optional(),
		status: z.enum(['ready', 'degraded']),
		deliveryStatus: z.enum(['unknownAfterDispatch']).optional(),
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

export const bridgeWorkerFileDisplayPatchEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		kind: z.literal('fileDisplayPatch'),
		surface: z.literal('fileView'),
		epoch: bridgeWorkerEpochSchema,
		sequence: bridgeWorkerSequenceSchema,
		projectionRevision: bridgeProductNonnegativeSequenceSchema,
		queryTransaction: z
			.discriminatedUnion('phase', [
				z
					.object({
						batchCount: z.number().int().positive(),
						batchIndex: z.number().int().nonnegative(),
						phase: z.literal('batch'),
						transactionId: bridgeProductIdentifierSchema,
					})
					.strict(),
				z
					.object({
						phase: z.literal('abort'),
						transactionId: bridgeProductIdentifierSchema,
					})
					.strict(),
			])
			.optional(),
		patches: z
			.array(bridgeWorkerFileDisplayPatchSchema)
			.max(BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT)
			.readonly(),
	})
	.strict()
	.superRefine((event, context): void => {
		if (
			event.queryTransaction?.phase === 'batch' &&
			event.queryTransaction.batchIndex >= event.queryTransaction.batchCount
		) {
			context.addIssue({
				code: 'custom',
				message: 'File query transaction batch index must be within its declared batch count.',
				path: ['queryTransaction', 'batchIndex'],
			});
		}
		const isAbort = event.queryTransaction?.phase === 'abort';
		if (isAbort !== (event.patches.length === 0)) {
			context.addIssue({
				code: 'custom',
				message: 'Only File query abort events may carry an empty patch list.',
				path: ['patches'],
			});
		}
	});

export const bridgeWorkerFileRenderPatchSchema = z.discriminatedUnion('slice', [
	bridgeWorkerRowPaintPatchSchema,
	bridgeWorkerContentAvailabilityPatchSchema,
]);

export const bridgeWorkerFileRenderPatchEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		...bridgeWorkerSurfacePublicationEnvelopeShape,
		kind: z.literal('fileRenderPatch'),
		patches: z
			.array(bridgeWorkerFileRenderPatchSchema)
			.min(1)
			.max(BRIDGE_WORKER_FILE_DISPLAY_PATCH_LIMIT)
			.readonly(),
		surface: z.literal('file'),
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

export const bridgeWorkerFilePierreRenderJobEventSchema = bridgeWorkerServerToMainBaseSchema
	.extend({
		...bridgeWorkerSurfacePublicationEnvelopeShape,
		job: bridgeWorkerPierreRenderJobSchema,
		kind: z.literal('filePierreRenderJob'),
		surface: z.literal('file'),
	})
	.strict()
	.superRefine((event, context): void => {
		if (event.job.renderKind !== 'fileText' || event.job.payload.kind !== 'codeViewFileItem') {
			context.addIssue({
				code: 'custom',
				message: 'File Pierre publications require a fileText CodeView File job.',
				path: ['job'],
			});
		}
	});

export const bridgeWorkerServerToMainMessageSchema = z.discriminatedUnion('kind', [
	bridgeWorkerHealthEventSchema,
	bridgeWorkerSlicePatchEventSchema,
	bridgeWorkerFileDisplayPatchEventSchema,
	bridgeWorkerFileRenderPatchEventSchema,
	bridgeWorkerSubscriptionEventSchema,
	bridgeWorkerPierreRenderJobEventSchema,
	bridgeWorkerFilePierreRenderJobEventSchema,
]);

export type BridgeWorkerHealthEvent = z.infer<typeof bridgeWorkerHealthEventSchema>;
export type BridgeWorkerSlicePatchEvent = z.infer<typeof bridgeWorkerSlicePatchEventSchema>;
export type BridgeWorkerFileDisplayPatchEvent = z.infer<
	typeof bridgeWorkerFileDisplayPatchEventSchema
>;
export type BridgeWorkerFileRenderPatch = z.infer<typeof bridgeWorkerFileRenderPatchSchema>;
type BridgeWorkerFileRenderPatchEventValue = z.infer<typeof bridgeWorkerFileRenderPatchEventSchema>;
export type BridgeWorkerFileRenderPatchEvent = BridgeWorkerSurfacePublicationEnvelope<
	'file',
	BridgeWorkerFileRenderPatchEventValue
>;
export type BridgeWorkerSubscriptionEvent = z.infer<typeof bridgeWorkerSubscriptionEventSchema>;
export type BridgeWorkerPierreRenderJobEvent = z.infer<
	typeof bridgeWorkerPierreRenderJobEventSchema
>;
type BridgeWorkerFilePierreRenderJobEventValue = z.infer<
	typeof bridgeWorkerFilePierreRenderJobEventSchema
>;
export type BridgeWorkerFilePierreRenderJobEvent = BridgeWorkerSurfacePublicationEnvelope<
	'file',
	BridgeWorkerFilePierreRenderJobEventValue
>;
export type BridgeWorkerServerToMainMessage = z.infer<typeof bridgeWorkerServerToMainMessageSchema>;
