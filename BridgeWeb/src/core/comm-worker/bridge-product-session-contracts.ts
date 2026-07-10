import { z } from 'zod';

export const BRIDGE_PRODUCT_WIRE_VERSION = 1 as const;
export const BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH = 32;
export const BRIDGE_PRODUCT_MAXIMUM_CONTROL_REQUEST_BYTES = 64 * 1024;
export const BRIDGE_PRODUCT_MAXIMUM_STREAM_FRAME_BYTES = 256 * 1024;
export const BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES = 64;
export const BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES = 4 * 1024 * 1024;
export const BRIDGE_PRODUCT_MAXIMUM_RESOURCE_BYTES = 2 * 1024 * 1024;
export const BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE = 1;

const bridgeProductMaximumJSONCollectionCount = 64;
const bridgeProductMaximumJSONDepth = 8;
const bridgeProductMaximumJSONValueStringBytes = 256;

const bridgeProductIdentifierSchema = z
	.string()
	.min(1)
	.regex(/^[A-Za-z0-9._:-]+$/)
	.refine(
		(value) => new TextEncoder().encode(value).byteLength <= 128,
		'Bridge product identifiers cannot exceed 128 UTF-8 bytes.',
	);
const bridgeProductOpaqueReferenceSchema = z
	.string()
	.min(1)
	.regex(/^[\u0021-\u007e]+$/)
	.refine(
		(value) => new TextEncoder().encode(value).byteLength <= 256,
		'Bridge product references cannot exceed 256 UTF-8 bytes.',
	);
const bridgeProductRequestSequenceSchema = z.number().int().positive().max(Number.MAX_SAFE_INTEGER);
const bridgeProductGenerationSchema = z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER);
const bridgeProductSurfaceSchema = z.enum(['review', 'file']);
const bridgeProductPayloadKeySchema = z
	.string()
	.min(1)
	.refine(
		(value) => new TextEncoder().encode(value).byteLength <= 128,
		'Bridge product payload keys cannot exceed 128 UTF-8 bytes.',
	);
export type BridgeProductJSONValue =
	| null
	| boolean
	| number
	| string
	| readonly BridgeProductJSONValue[]
	| { readonly [key: string]: BridgeProductJSONValue };
const bridgeProductJSONValueSchema: z.ZodType<BridgeProductJSONValue> = z.lazy(() =>
	z.union([
		z.null(),
		z.boolean(),
		z.number().refine((value) => Math.abs(value) <= Number.MAX_SAFE_INTEGER),
		z
			.string()
			.refine(
				(value) =>
					new TextEncoder().encode(value).byteLength <= bridgeProductMaximumJSONValueStringBytes,
				'Bridge product JSON strings cannot exceed 256 UTF-8 bytes.',
			),
		z.array(bridgeProductJSONValueSchema).max(bridgeProductMaximumJSONCollectionCount).readonly(),
		z
			.record(bridgeProductPayloadKeySchema, bridgeProductJSONValueSchema)
			.refine((value) => Object.keys(value).length <= bridgeProductMaximumJSONCollectionCount)
			.readonly(),
	]),
);
const bridgeProductPayloadSchema = z
	.record(bridgeProductPayloadKeySchema, bridgeProductJSONValueSchema)
	.refine((value) => Object.keys(value).length <= bridgeProductMaximumJSONCollectionCount)
	.superRefine((value, context) => {
		if (bridgeProductJSONValueDepth(value) > bridgeProductMaximumJSONDepth) {
			context.addIssue({
				code: 'custom',
				message: 'Bridge product JSON payload exceeds the shared depth cap.',
			});
		}
	});
const bridgeProductSafeMessageSchema = z
	.string()
	.min(1)
	.refine(
		(value) => new TextEncoder().encode(value).byteLength <= 256,
		'Bridge product safe messages cannot exceed 256 UTF-8 bytes.',
	);

const bridgeProductControlRequestBaseShape = {
	wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
	paneSessionId: bridgeProductIdentifierSchema,
	workerInstanceId: bridgeProductIdentifierSchema,
	requestId: bridgeProductIdentifierSchema,
	requestSequence: bridgeProductRequestSequenceSchema,
} as const;

const bridgeProductControlResponseBaseShape = {
	wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
	paneSessionId: bridgeProductIdentifierSchema,
	workerInstanceId: bridgeProductIdentifierSchema,
	requestId: bridgeProductIdentifierSchema,
	requestSequence: bridgeProductRequestSequenceSchema,
} as const;

const bridgeProductStreamFrameBaseShape = {
	wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
	paneSessionId: bridgeProductIdentifierSchema,
	workerInstanceId: bridgeProductIdentifierSchema,
	surface: bridgeProductSurfaceSchema,
	streamId: bridgeProductIdentifierSchema,
	sourceGeneration: bridgeProductGenerationSchema,
	workerEpoch: bridgeProductGenerationSchema,
} as const;

export const bridgeProductCommandNameSchema = z.enum([
	'review.load',
	'review.refresh',
	'review.markFileViewed',
	'review.metadataInterest.update',
	'file.open',
	'file.refresh',
	'file.requestDescriptor',
	'viewerMode.update',
]);

export const bridgeProductStreamDataFrameKindSchema = z.enum([
	'review.snapshot',
	'review.delta',
	'review.contentDescriptor',
	'file.snapshot',
	'file.delta',
	'file.contentDescriptor',
	'surface.health',
]);

const bridgeProductStreamDataPayloadSchema = z
	.object({
		frameKind: bridgeProductStreamDataFrameKindSchema,
		body: bridgeProductPayloadSchema,
	})
	.strict();

const bridgeProductCommandSchema = z
	.object({
		name: bridgeProductCommandNameSchema,
		payload: bridgeProductPayloadSchema,
	})
	.strict();

// This freezes the transport envelope. Each command owner still validates its payload schema.
export const bridgeProductControlRequestSchema = z.discriminatedUnion('kind', [
	z
		.object({
			...bridgeProductControlRequestBaseShape,
			kind: z.literal('workerSession.open'),
		})
		.strict(),
	z
		.object({
			...bridgeProductControlRequestBaseShape,
			kind: z.literal('product.command'),
			surface: bridgeProductSurfaceSchema,
			sourceGeneration: bridgeProductGenerationSchema,
			workerEpoch: bridgeProductGenerationSchema,
			command: bridgeProductCommandSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductControlRequestBaseShape,
			kind: z.literal('stream.open'),
			surface: bridgeProductSurfaceSchema,
			sourceGeneration: bridgeProductGenerationSchema,
			workerEpoch: bridgeProductGenerationSchema,
			streamId: bridgeProductIdentifierSchema,
			sourceRef: bridgeProductOpaqueReferenceSchema,
			resumeFromSequence: bridgeProductGenerationSchema.nullable(),
		})
		.strict(),
	z
		.object({
			...bridgeProductControlRequestBaseShape,
			kind: z.literal('stream.cancel'),
			surface: bridgeProductSurfaceSchema,
			streamId: bridgeProductIdentifierSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductControlRequestBaseShape,
			kind: z.literal('workerSession.resync'),
			lastAcceptedRequestSequence: bridgeProductGenerationSchema,
			activeStreamIds: z
				.array(bridgeProductIdentifierSchema)
				.max(64)
				.refine((streamIds) => new Set(streamIds).size === streamIds.length)
				.readonly(),
		})
		.strict(),
]);

export const bridgeProductRequestErrorCodeSchema = z.enum([
	'invalid_request',
	'unauthorized',
	'stale_worker',
	'sequence_conflict',
	'resync_required',
	'payload_too_large',
	'unknown_command',
	'internal',
]);

export const bridgeProductControlResponseSchema = z.discriminatedUnion('kind', [
	z
		.object({
			...bridgeProductControlResponseBaseShape,
			kind: z.literal('workerSession.accepted'),
		})
		.strict(),
	z
		.object({
			...bridgeProductControlResponseBaseShape,
			kind: z.literal('command.accepted'),
		})
		.strict(),
	z
		.object({
			...bridgeProductControlResponseBaseShape,
			kind: z.literal('stream.cancelled'),
			streamId: bridgeProductIdentifierSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductControlResponseBaseShape,
			kind: z.literal('request.error'),
			code: bridgeProductRequestErrorCodeSchema,
			retryable: z.boolean(),
			retryAfterMilliseconds: bridgeProductGenerationSchema.optional(),
			nextExpectedRequestSequence: bridgeProductRequestSequenceSchema.optional(),
			safeMessage: bridgeProductSafeMessageSchema.optional(),
		})
		.strict(),
]);

export const bridgeProductStreamFrameSchema = z.discriminatedUnion('kind', [
	z
		.object({
			...bridgeProductStreamFrameBaseShape,
			kind: z.literal('stream.accepted'),
			streamSequence: z.literal(0),
			resumeDisposition: z.enum(['resumed', 'snapshot_required']),
		})
		.strict(),
	z
		.object({
			...bridgeProductStreamFrameBaseShape,
			kind: z.literal('stream.data'),
			streamSequence: bridgeProductRequestSequenceSchema,
			payload: bridgeProductStreamDataPayloadSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductStreamFrameBaseShape,
			kind: z.literal('stream.reset'),
			streamSequence: bridgeProductRequestSequenceSchema,
			reason: z.enum(['producer_overflow', 'sequence_gap', 'stale_source', 'snapshot_required']),
		})
		.strict(),
	z
		.object({
			...bridgeProductStreamFrameBaseShape,
			kind: z.literal('stream.end'),
			streamSequence: bridgeProductRequestSequenceSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductStreamFrameBaseShape,
			kind: z.literal('stream.error'),
			streamSequence: bridgeProductRequestSequenceSchema,
			code: bridgeProductRequestErrorCodeSchema,
			retryable: z.boolean(),
			safeMessage: bridgeProductSafeMessageSchema.optional(),
		})
		.strict(),
]);

export const bridgeProductResourceRequestIdentitySchema = z
	.object({
		wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
		paneSessionId: bridgeProductIdentifierSchema,
		workerInstanceId: bridgeProductIdentifierSchema,
		surface: bridgeProductSurfaceSchema,
		sourceGeneration: bridgeProductGenerationSchema,
		workerEpoch: bridgeProductGenerationSchema,
		resourceRequestId: bridgeProductIdentifierSchema,
		leaseId: bridgeProductIdentifierSchema,
		resourceKind: z.enum(['review.content', 'file.content']),
		resourceRef: bridgeProductOpaqueReferenceSchema,
		maximumBytes: bridgeProductRequestSequenceSchema.max(BRIDGE_PRODUCT_MAXIMUM_RESOURCE_BYTES),
	})
	.strict();

const bridgeProductCapabilityBytesSchema = z
	.array(z.number().int().min(0).max(255))
	.length(BRIDGE_PRODUCT_CAPABILITY_BYTE_LENGTH)
	.readonly();

export const bridgeProductBootstrapPolicySchema = z
	.object({
		maximumControlRequestBytes: z
			.number()
			.int()
			.positive()
			.max(BRIDGE_PRODUCT_MAXIMUM_CONTROL_REQUEST_BYTES),
		maximumStreamFrameBytes: z
			.number()
			.int()
			.positive()
			.max(BRIDGE_PRODUCT_MAXIMUM_STREAM_FRAME_BYTES),
		maximumQueuedStreamFrames: z
			.number()
			.int()
			.positive()
			.max(BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_FRAMES),
		maximumQueuedStreamBytes: z
			.number()
			.int()
			.positive()
			.max(BRIDGE_PRODUCT_MAXIMUM_QUEUED_STREAM_BYTES),
		maximumResourceBytes: z.number().int().positive().max(BRIDGE_PRODUCT_MAXIMUM_RESOURCE_BYTES),
		terminalFrameReserve: z.literal(BRIDGE_PRODUCT_TERMINAL_FRAME_RESERVE),
	})
	.strict();

export const bridgeProductRouteVocabularySchema = z
	.object({
		command: z
			.object({
				method: z.literal('POST'),
				url: z.literal('agentstudio://rpc/command'),
			})
			.strict(),
		stream: z
			.object({
				method: z.literal('POST'),
				url: z.literal('agentstudio://rpc/stream'),
			})
			.strict(),
		resource: z
			.object({
				method: z.literal('GET'),
				urlPrefix: z.literal('agentstudio://resource/'),
			})
			.strict(),
	})
	.strict();

export const bridgeProductSessionBootstrapSchema = z
	.object({
		kind: z.literal('productSession.bootstrap'),
		wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
		paneSessionId: bridgeProductIdentifierSchema,
		workerInstanceId: bridgeProductIdentifierSchema,
		initialSurface: bridgeProductSurfaceSchema,
		productCapabilityBytes: bridgeProductCapabilityBytesSchema,
		policy: bridgeProductBootstrapPolicySchema,
		routes: bridgeProductRouteVocabularySchema,
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
		kind: z.literal('bridgePaneCommWorker.install'),
		wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
		paneSessionId: bridgeProductIdentifierSchema,
		workerInstanceId: bridgeProductIdentifierSchema,
		productCapability: bridgeProductCapabilitySchema,
		productPort: bridgeProductMessagePortSchema,
	})
	.strict();

export type BridgeProductControlRequest = z.infer<typeof bridgeProductControlRequestSchema>;
export type BridgeProductControlResponse = z.infer<typeof bridgeProductControlResponseSchema>;
export type BridgeProductStreamFrame = z.infer<typeof bridgeProductStreamFrameSchema>;
export type BridgeProductResourceRequestIdentity = z.infer<
	typeof bridgeProductResourceRequestIdentitySchema
>;
export type BridgeProductSessionBootstrap = z.infer<typeof bridgeProductSessionBootstrapSchema>;
export type BridgePaneCommWorkerInstall = z.infer<typeof bridgePaneCommWorkerInstallSchema>;

export interface BridgePaneCommWorkerInstallTarget {
	postMessage(message: unknown, transferList: Transferable[]): void;
}

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

export function encodeBridgeProductStreamFrame(frame: BridgeProductStreamFrame): Uint8Array {
	const validatedFrame = bridgeProductStreamFrameSchema.parse(frame);
	const frameBytes = new TextEncoder().encode(JSON.stringify(validatedFrame));
	const encodedFrame = new Uint8Array(4 + frameBytes.byteLength);
	new DataView(encodedFrame.buffer).setUint32(0, frameBytes.byteLength, false);
	encodedFrame.set(frameBytes, 4);
	return encodedFrame;
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

function bridgeProductJSONValueDepth(value: BridgeProductJSONValue): number {
	if (Array.isArray(value)) {
		return 1 + Math.max(0, ...value.map(bridgeProductJSONValueDepth));
	}
	if (typeof value === 'object' && value !== null) {
		return 1 + Math.max(0, ...Object.values(value).map(bridgeProductJSONValueDepth));
	}
	return 0;
}
