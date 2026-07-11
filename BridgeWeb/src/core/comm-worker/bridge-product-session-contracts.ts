import { z } from 'zod';

import {
	bridgeProductCallRequestSchema,
	bridgeProductCallResultSchema,
} from './bridge-product-call-contracts.js';
import { bridgeProductContentIdentitySchema } from './bridge-product-content-contracts.js';
import {
	BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_CONTROL_REQUEST_SEQUENCE,
	BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES,
	BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES,
	BRIDGE_PRODUCT_MAXIMUM_RESUMABLE_STREAM_SEQUENCE,
	BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE,
	BRIDGE_PRODUCT_WIRE_VERSION,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductOpaqueReferenceSchema,
	bridgeProductPositiveSequenceSchema,
	bridgeProductRequestErrorCodeSchema,
	bridgeProductResetReasonSchema,
	bridgeProductSafeMessageSchema,
	bridgeProductSha256Schema,
} from './bridge-product-contract-primitives.js';
import {
	BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT,
	bridgeProductFileMetadataInterestDeltaSchema,
	bridgeProductFileMetadataSubscriptionDataSchema,
	bridgeProductReviewMetadataInterestDeltaSchema,
	bridgeProductReviewMetadataSubscriptionDataSchema,
	bridgeProductSubscriptionInterestDeltaItemCount,
	type BridgeProductSubscriptionInterestDeltaWire,
	bridgeProductSubscriptionKindSchema,
	bridgeProductSubscriptionOpenSchema,
	bridgeProductSurfaceForSubscriptionKind,
} from './bridge-product-subscription-contracts.js';

const bridgeProductControlIdentityShape = {
	paneSessionId: bridgeProductIdentifierSchema,
	requestId: bridgeProductIdentifierSchema,
	requestSequence: bridgeProductPositiveSequenceSchema.max(
		BRIDGE_PRODUCT_MAXIMUM_CONTROL_REQUEST_SEQUENCE,
	),
	wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
	workerInstanceId: bridgeProductIdentifierSchema,
} as const;

const bridgeProductSurfaceRequestIdentityShape = {
	...bridgeProductControlIdentityShape,
	workerDerivationEpoch: bridgeProductNonnegativeSequenceSchema,
} as const;

const bridgeProductSubscriptionControlIdentityShape = {
	subscriptionId: bridgeProductIdentifierSchema,
	subscriptionKind: bridgeProductSubscriptionKindSchema,
} as const;

const bridgeProductActiveSubscriptionSchema = z
	.object({
		...bridgeProductSubscriptionControlIdentityShape,
		interestRevision: bridgeProductNonnegativeSequenceSchema,
		interestSha256: bridgeProductSha256Schema,
		workerDerivationEpoch: bridgeProductNonnegativeSequenceSchema,
	})
	.strict();

const bridgeProductSubscriptionUpdateBatchBaseShape = {
	...bridgeProductSurfaceRequestIdentityShape,
	baseInterestRevision: bridgeProductNonnegativeSequenceSchema,
	baseInterestSha256: bridgeProductSha256Schema,
	batchCount: bridgeProductPositiveSequenceSchema.max(
		BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT,
	),
	batchIndex: bridgeProductNonnegativeSequenceSchema,
	kind: z.literal('subscription.updateBatch'),
	subscriptionId: bridgeProductIdentifierSchema,
	targetInterestRevision: bridgeProductPositiveSequenceSchema,
	targetInterestSha256: bridgeProductSha256Schema,
	totalDeltaItemCount: bridgeProductPositiveSequenceSchema.max(
		BRIDGE_PRODUCT_MAXIMUM_SUBSCRIPTION_DELTA_ITEM_COUNT,
	),
	updateId: bridgeProductIdentifierSchema,
} as const;

const bridgeProductSubscriptionUpdateBatchRequestSchema = z
	.discriminatedUnion('subscriptionKind', [
		z
			.object({
				...bridgeProductSubscriptionUpdateBatchBaseShape,
				delta: bridgeProductFileMetadataInterestDeltaSchema,
				subscriptionKind: z.literal('file.metadata'),
			})
			.strict(),
		z
			.object({
				...bridgeProductSubscriptionUpdateBatchBaseShape,
				delta: bridgeProductReviewMetadataInterestDeltaSchema,
				subscriptionKind: z.literal('review.metadata'),
			})
			.strict(),
	])
	.superRefine((request, context): void => {
		validateBridgeProductSubscriptionUpdateBatch(request, context);
	});

export const bridgeProductControlRequestSchema = z.discriminatedUnion('kind', [
	z
		.object({
			...bridgeProductControlIdentityShape,
			kind: z.literal('workerSession.open'),
			request: z.null(),
		})
		.strict(),
	z
		.object({
			...bridgeProductSurfaceRequestIdentityShape,
			call: bridgeProductCallRequestSchema,
			kind: z.literal('product.call'),
		})
		.strict(),
	z
		.object({
			...bridgeProductSurfaceRequestIdentityShape,
			kind: z.literal('subscription.open'),
			subscription: bridgeProductSubscriptionOpenSchema,
			subscriptionId: bridgeProductIdentifierSchema,
		})
		.strict(),
	bridgeProductSubscriptionUpdateBatchRequestSchema,
	z
		.object({
			...bridgeProductSurfaceRequestIdentityShape,
			...bridgeProductSubscriptionControlIdentityShape,
			kind: z.literal('subscription.cancel'),
		})
		.strict(),
	z
		.object({
			...bridgeProductControlIdentityShape,
			activeSubscriptions: z
				.array(bridgeProductActiveSubscriptionSchema)
				.max(64)
				.refine(
					(subscriptions) =>
						new Set(subscriptions.map((subscription) => subscription.subscriptionId)).size ===
						subscriptions.length,
					'Duplicate active Bridge product subscription id.',
				)
				.readonly(),
			kind: z.literal('workerSession.resync'),
			lastAcceptedRequestSequence: bridgeProductNonnegativeSequenceSchema.max(
				BRIDGE_PRODUCT_MAXIMUM_CONTROL_REQUEST_SEQUENCE - 1,
			),
			lastAcceptedStreamSequence: bridgeProductNonnegativeSequenceSchema.max(
				BRIDGE_PRODUCT_MAXIMUM_RESUMABLE_STREAM_SEQUENCE,
			),
		})
		.strict()
		.superRefine((request, context): void => {
			validateBridgeProductResyncSurfaceEpochs(request.activeSubscriptions, context);
		}),
]);

export const bridgeProductControlResponseSchema = z.discriminatedUnion('kind', [
	z
		.object({
			...bridgeProductControlIdentityShape,
			kind: z.literal('workerSession.accepted'),
			result: z.null(),
		})
		.strict(),
	z
		.object({
			...bridgeProductControlIdentityShape,
			call: bridgeProductCallResultSchema,
			kind: z.literal('call.completed'),
		})
		.strict(),
	z
		.object({
			...bridgeProductControlIdentityShape,
			...bridgeProductSubscriptionControlIdentityShape,
			interestRevision: z.literal(0),
			interestSha256: bridgeProductSha256Schema,
			kind: z.literal('subscription.openAccepted'),
		})
		.strict(),
	z
		.object({
			...bridgeProductControlIdentityShape,
			...bridgeProductSubscriptionControlIdentityShape,
			batchIndex: bridgeProductNonnegativeSequenceSchema,
			disposition: z.enum(['staged', 'committed']),
			kind: z.literal('subscription.updateBatchAccepted'),
			targetInterestRevision: bridgeProductPositiveSequenceSchema,
			targetInterestSha256: bridgeProductSha256Schema,
			updateId: bridgeProductIdentifierSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductControlIdentityShape,
			...bridgeProductSubscriptionControlIdentityShape,
			kind: z.literal('subscription.cancelAccepted'),
		})
		.strict(),
	z
		.object({
			...bridgeProductControlIdentityShape,
			kind: z.literal('resync.accepted'),
			nextExpectedRequestSequence: bridgeProductPositiveSequenceSchema,
			resumeFromStreamSequence: bridgeProductNonnegativeSequenceSchema.max(
				BRIDGE_PRODUCT_MAXIMUM_RESUMABLE_STREAM_SEQUENCE,
			),
		})
		.strict(),
	z
		.object({
			...bridgeProductControlIdentityShape,
			code: bridgeProductRequestErrorCodeSchema,
			kind: z.literal('request.error'),
			nextExpectedRequestSequence: bridgeProductPositiveSequenceSchema.nullable(),
			retryAfterMilliseconds: bridgeProductNonnegativeSequenceSchema.nullable(),
			retryable: z.boolean(),
			safeMessage: bridgeProductSafeMessageSchema.nullable(),
		})
		.strict(),
]);

export const bridgeProductMetadataStreamRequestSchema = z
	.object({
		kind: z.literal('metadataStream.open'),
		metadataStreamId: bridgeProductIdentifierSchema,
		paneSessionId: bridgeProductIdentifierSchema,
		resumeFromStreamSequence: bridgeProductNonnegativeSequenceSchema
			.max(BRIDGE_PRODUCT_MAXIMUM_RESUMABLE_STREAM_SEQUENCE)
			.nullable(),
		wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
		workerInstanceId: bridgeProductIdentifierSchema,
	})
	.strict();

const bridgeProductMetadataFrameIdentityShape = {
	metadataStreamId: bridgeProductIdentifierSchema,
	paneSessionId: bridgeProductIdentifierSchema,
	streamSequence: bridgeProductNonnegativeSequenceSchema,
	wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
	workerInstanceId: bridgeProductIdentifierSchema,
} as const;

const bridgeProductSubscriptionFrameIdentityShape = {
	cursor: bridgeProductOpaqueReferenceSchema.nullable(),
	interestRevision: bridgeProductNonnegativeSequenceSchema,
	interestSha256: bridgeProductSha256Schema,
	sourceGeneration: bridgeProductNonnegativeSequenceSchema,
	subscriptionId: bridgeProductIdentifierSchema,
	subscriptionKind: bridgeProductSubscriptionKindSchema,
	subscriptionSequence: bridgeProductNonnegativeSequenceSchema,
	workerDerivationEpoch: bridgeProductNonnegativeSequenceSchema,
} as const;

const bridgeProductSubscriptionDataFrameBaseShape = {
	...bridgeProductMetadataFrameIdentityShape,
	...bridgeProductSubscriptionFrameIdentityShape,
	kind: z.literal('subscription.data'),
	streamSequence: bridgeProductPositiveSequenceSchema,
	subscriptionSequence: bridgeProductPositiveSequenceSchema,
} as const;

const bridgeProductSubscriptionDataFrameSchema = z.discriminatedUnion('subscriptionKind', [
	z
		.object({
			...bridgeProductSubscriptionDataFrameBaseShape,
			data: bridgeProductFileMetadataSubscriptionDataSchema,
			subscriptionKind: z.literal('file.metadata'),
		})
		.strict(),
	z
		.object({
			...bridgeProductSubscriptionDataFrameBaseShape,
			data: bridgeProductReviewMetadataSubscriptionDataSchema,
			subscriptionKind: z.literal('review.metadata'),
		})
		.strict(),
]);

export const bridgeProductMetadataFrameSchema = z.discriminatedUnion('kind', [
	z
		.object({
			...bridgeProductMetadataFrameIdentityShape,
			kind: z.literal('metadataStream.accepted'),
			resumeDisposition: z.enum(['resumed', 'snapshot_required']),
			streamSequence: bridgeProductNonnegativeSequenceSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductMetadataFrameIdentityShape,
			...bridgeProductSubscriptionFrameIdentityShape,
			interestRevision: z.literal(0),
			kind: z.literal('subscription.accepted'),
			streamSequence: bridgeProductPositiveSequenceSchema,
			subscriptionSequence: z.literal(0),
		})
		.strict(),
	z
		.object({
			...bridgeProductMetadataFrameIdentityShape,
			...bridgeProductSubscriptionFrameIdentityShape,
			kind: z.literal('subscription.interestsCommitted'),
			streamSequence: bridgeProductPositiveSequenceSchema,
			subscriptionSequence: bridgeProductPositiveSequenceSchema,
			updateId: bridgeProductIdentifierSchema,
		})
		.strict(),
	bridgeProductSubscriptionDataFrameSchema,
	z
		.object({
			...bridgeProductMetadataFrameIdentityShape,
			...bridgeProductSubscriptionFrameIdentityShape,
			kind: z.literal('subscription.reset'),
			reason: bridgeProductResetReasonSchema,
			streamSequence: bridgeProductPositiveSequenceSchema,
			subscriptionSequence: bridgeProductPositiveSequenceSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductMetadataFrameIdentityShape,
			...bridgeProductSubscriptionFrameIdentityShape,
			kind: z.literal('subscription.end'),
			streamSequence: bridgeProductPositiveSequenceSchema,
			subscriptionSequence: bridgeProductPositiveSequenceSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductMetadataFrameIdentityShape,
			...bridgeProductSubscriptionFrameIdentityShape,
			kind: z.literal('subscription.cancelled'),
			streamSequence: bridgeProductPositiveSequenceSchema,
			subscriptionSequence: bridgeProductPositiveSequenceSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductMetadataFrameIdentityShape,
			contentRequestId: bridgeProductIdentifierSchema,
			disposition: z.enum(['stopped', 'already_terminal']),
			identity: bridgeProductContentIdentitySchema,
			kind: z.literal('content.cancelled'),
			leaseId: bridgeProductIdentifierSchema,
			streamSequence: bridgeProductPositiveSequenceSchema,
			workerDerivationEpoch: bridgeProductNonnegativeSequenceSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductMetadataFrameIdentityShape,
			code: bridgeProductRequestErrorCodeSchema,
			kind: z.literal('metadataStream.error'),
			retryable: z.boolean(),
			safeMessage: bridgeProductSafeMessageSchema.nullable(),
			streamSequence: bridgeProductPositiveSequenceSchema,
		})
		.strict(),
]);

const bridgeProductCapabilityBytesSchema = z
	.array(z.number().int().min(0).max(255))
	.length(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH)
	.readonly();

export const bridgeProductBootstrapPolicySchema = z
	.object({
		maximumContentBytes: z.number().int().positive().max(BRIDGE_PRODUCT_MAXIMUM_CONTENT_BYTES),
		maximumRequestBodyBytes: z
			.number()
			.int()
			.positive()
			.max(BRIDGE_PRODUCT_MAXIMUM_REQUEST_BODY_BYTES),
		maximumMetadataFrameBytes: z
			.number()
			.int()
			.positive()
			.max(BRIDGE_PRODUCT_MAXIMUM_METADATA_FRAME_BYTES),
		maximumQueuedStreamBytes: z
			.number()
			.int()
			.positive()
			.max(BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES),
		maximumQueuedStreamFrames: z
			.number()
			.int()
			.positive()
			.max(BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES),
		terminalFrameReserve: z.literal(BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE),
	})
	.strict();

export const bridgeProductSessionBootstrapSchema = z
	.object({
		kind: z.literal('productSession.bootstrap'),
		paneSessionId: bridgeProductIdentifierSchema,
		policy: bridgeProductBootstrapPolicySchema,
		wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
		workerInstanceId: bridgeProductIdentifierSchema,
	})
	.strict();

const bridgeProductCapabilitySchema = z.custom<ArrayBuffer>(
	(value) =>
		value instanceof ArrayBuffer && value.byteLength === BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH,
	'Bridge product capability must be one 32-byte ArrayBuffer.',
);
const bridgeProductMessagePortSchema = z.custom<MessagePort>(
	(value) =>
		typeof value === 'object' &&
		value !== null &&
		'postMessage' in value &&
		typeof value.postMessage === 'function' &&
		'close' in value &&
		typeof value.close === 'function',
	'Bridge pane comm-worker install requires a transferable MessagePort.',
);

export const bridgePaneCommWorkerInstallSchema = z
	.object({
		bootstrap: bridgeProductSessionBootstrapSchema,
		kind: z.literal('bridgePaneCommWorker.install'),
		productCapability: bridgeProductCapabilitySchema,
		productPort: bridgeProductMessagePortSchema,
	})
	.strict();

export type BridgeProductControlRequest = z.infer<typeof bridgeProductControlRequestSchema>;
export type BridgeProductControlResponse = z.infer<typeof bridgeProductControlResponseSchema>;
export type BridgeProductMetadataStreamRequest = z.infer<
	typeof bridgeProductMetadataStreamRequestSchema
>;
export type BridgeProductMetadataFrame = z.infer<typeof bridgeProductMetadataFrameSchema>;
export type BridgeProductSessionBootstrap = z.infer<typeof bridgeProductSessionBootstrapSchema>;
export type BridgePaneCommWorkerInstall = z.infer<typeof bridgePaneCommWorkerInstallSchema>;

export type BridgePaneCommWorkerInstallTarget = {
	postMessage(message: BridgePaneCommWorkerInstall, transferList: readonly Transferable[]): void;
};

export function postBridgePaneCommWorkerInstall(
	target: BridgePaneCommWorkerInstallTarget,
	install: BridgePaneCommWorkerInstall,
): void {
	const validatedInstall = bridgePaneCommWorkerInstallSchema.parse(install);
	target.postMessage(validatedInstall, [
		validatedInstall.productPort,
		validatedInstall.productCapability,
	]);
	if (validatedInstall.productCapability.byteLength !== 0) {
		throw new Error('Bridge product capability did not detach after pane-worker install.');
	}
}

export function bridgeProductMetadataAcceptedStreamSequence(
	request: BridgeProductMetadataStreamRequest,
): number {
	const validatedRequest = bridgeProductMetadataStreamRequestSchema.parse(request);
	return validatedRequest.resumeFromStreamSequence === null
		? 0
		: validatedRequest.resumeFromStreamSequence + 1;
}

export function encodeBridgeProductCapabilityHeader(
	capability: ArrayBuffer | ArrayBufferView | readonly number[],
): string {
	const capabilityBytes =
		capability instanceof ArrayBuffer
			? new Uint8Array(capability)
			: ArrayBuffer.isView(capability)
				? new Uint8Array(capability.buffer, capability.byteOffset, capability.byteLength)
				: capability;
	const validatedBytes = bridgeProductCapabilityBytesSchema.parse([...capabilityBytes]);
	let binaryValue = '';
	for (const byte of validatedBytes) {
		binaryValue += String.fromCharCode(byte);
	}
	return globalThis.btoa(binaryValue).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/u, '');
}

function validateBridgeProductSubscriptionUpdateBatch(
	request: {
		readonly baseInterestRevision: number;
		readonly batchCount: number;
		readonly batchIndex: number;
		readonly delta: BridgeProductSubscriptionInterestDeltaWire;
		readonly targetInterestRevision: number;
		readonly totalDeltaItemCount: number;
	},
	context: z.RefinementCtx,
): void {
	const batchItemCount = bridgeProductSubscriptionInterestDeltaItemCount(request.delta);
	if (request.targetInterestRevision !== request.baseInterestRevision + 1) {
		context.addIssue({
			code: 'custom',
			message: 'Subscription update must advance exactly one interest revision.',
			path: ['targetInterestRevision'],
		});
	}
	if (request.batchIndex >= request.batchCount) {
		context.addIssue({
			code: 'custom',
			message: 'Subscription update batch index must be below its batch count.',
			path: ['batchIndex'],
		});
	}
	if (batchItemCount === 0 || batchItemCount > request.totalDeltaItemCount) {
		context.addIssue({
			code: 'custom',
			message: 'Subscription update batch item count must fit its declared total.',
			path: ['delta'],
		});
	}
	if (request.batchCount > request.totalDeltaItemCount) {
		context.addIssue({
			code: 'custom',
			message: 'Subscription update cannot declare more nonempty batches than items.',
			path: ['batchCount'],
		});
	}
}

function validateBridgeProductResyncSurfaceEpochs(
	activeSubscriptions: readonly {
		readonly subscriptionKind: z.infer<typeof bridgeProductSubscriptionKindSchema>;
		readonly workerDerivationEpoch: number;
	}[],
	context: z.RefinementCtx,
): void {
	const epochBySurface = new Map<'file' | 'review', number>();
	for (const [subscriptionIndex, activeSubscription] of activeSubscriptions.entries()) {
		const surface = bridgeProductSurfaceForSubscriptionKind(activeSubscription.subscriptionKind);
		const existingEpoch = epochBySurface.get(surface);
		if (existingEpoch === undefined) {
			epochBySurface.set(surface, activeSubscription.workerDerivationEpoch);
			continue;
		}
		if (existingEpoch !== activeSubscription.workerDerivationEpoch) {
			context.addIssue({
				code: 'custom',
				message: 'Active subscriptions for one surface must share one derivation epoch.',
				path: ['activeSubscriptions', subscriptionIndex, 'workerDerivationEpoch'],
			});
		}
	}
}
