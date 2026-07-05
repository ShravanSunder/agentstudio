import { z } from 'zod';

import {
	bridgeContentRoleSchema,
	bridgeReviewContentLineCountsByRoleSchema,
} from '../../foundation/review-package/bridge-review-package-schema.js';
import { bridgeWorkerPierreRenderJobSchema } from './bridge-worker-pierre-render-job.js';

export const BRIDGE_WORKER_WIRE_VERSION = 1 as const;

const bridgeWorkerRequestIdSchema = z.string().min(1);
const bridgeWorkerEpochSchema = z.number().int().nonnegative();
const bridgeWorkerSequenceSchema = z.number().int().nonnegative();

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

export const bridgeWorkerMainToServerCommandSchema = z.discriminatedUnion('command', [
	bridgeWorkerSelectCommandSchema,
	bridgeWorkerViewportCommandSchema,
	bridgeWorkerHoverCommandSchema,
	bridgeWorkerMarkFileViewedCommandSchema,
	bridgeWorkerModeCommandSchema,
]);

export const bridgeWorkerMainToServerMessageSchema = bridgeWorkerMainToServerCommandSchema;

export type BridgeWorkerSelectCommand = z.infer<typeof bridgeWorkerSelectCommandSchema>;
export type BridgeWorkerViewportCommand = z.infer<typeof bridgeWorkerViewportCommandSchema>;
export type BridgeWorkerHoverCommand = z.infer<typeof bridgeWorkerHoverCommandSchema>;
export type BridgeWorkerMarkFileViewedCommand = z.infer<
	typeof bridgeWorkerMarkFileViewedCommandSchema
>;
export type BridgeWorkerModeCommand = z.infer<typeof bridgeWorkerModeCommandSchema>;
export type BridgeWorkerMainToServerCommand = z.infer<typeof bridgeWorkerMainToServerCommandSchema>;
export type BridgeWorkerMainToServerMessage = BridgeWorkerMainToServerCommand;

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
