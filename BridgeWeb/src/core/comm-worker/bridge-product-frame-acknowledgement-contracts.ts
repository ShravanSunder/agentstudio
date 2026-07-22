import { z } from 'zod';

import {
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	BRIDGE_PRODUCT_WIRE_VERSION,
} from './bridge-product-contract-primitives.js';

const bridgeProductFrameAcknowledgementCommonIdentityShape = {
	paneSessionId: bridgeProductIdentifierSchema,
	wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
	workerInstanceId: bridgeProductIdentifierSchema,
} as const;

export const bridgeProductFrameAcknowledgementRequestSchema = z.discriminatedUnion('streamKind', [
	z
		.object({
			...bridgeProductFrameAcknowledgementCommonIdentityShape,
			kind: z.literal('stream.frameObserved'),
			metadataStreamId: bridgeProductIdentifierSchema,
			streamKind: z.literal('metadata'),
			streamSequence: bridgeProductNonnegativeSequenceSchema,
		})
		.strict(),
	z
		.object({
			...bridgeProductFrameAcknowledgementCommonIdentityShape,
			contentRequestId: bridgeProductIdentifierSchema,
			contentSequence: bridgeProductNonnegativeSequenceSchema,
			kind: z.literal('stream.frameObserved'),
			leaseId: bridgeProductIdentifierSchema,
			streamKind: z.literal('content'),
		})
		.strict(),
]);

export const bridgeProductFrameAcknowledgementRejectedStatusSchema = z.union([
	z.literal(400),
	z.literal(401),
	z.literal(403),
	z.literal(404),
	z.literal(405),
	z.literal(409),
	z.literal(413),
	z.literal(415),
]);

export type BridgeProductFrameAcknowledgementRequest = z.infer<
	typeof bridgeProductFrameAcknowledgementRequestSchema
>;
export type BridgeProductFrameAcknowledgementRejectedStatus = z.infer<
	typeof bridgeProductFrameAcknowledgementRejectedStatusSchema
>;
