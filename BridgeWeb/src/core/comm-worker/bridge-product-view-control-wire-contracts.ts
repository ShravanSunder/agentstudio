import { z } from 'zod';

import {
	BRIDGE_PRODUCT_MAXIMUM_CONTROL_REQUEST_SEQUENCE,
	BRIDGE_PRODUCT_WIRE_VERSION,
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductPositiveSequenceSchema,
} from './bridge-product-contract-primitives.js';
import { bridgeProductMetadataApplicationKindSchema } from './bridge-product-metadata-application-protocol.js';

const controlCorrelationShape = {
	paneSessionId: bridgeProductIdentifierSchema,
	requestId: bridgeProductIdentifierSchema,
	requestSequence: bridgeProductPositiveSequenceSchema.max(
		BRIDGE_PRODUCT_MAXIMUM_CONTROL_REQUEST_SEQUENCE,
	),
	wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
	workerInstanceId: bridgeProductIdentifierSchema,
} as const;

const viewControlShape = {
	...controlCorrelationShape,
	handle: bridgeProductIdentifierSchema,
	scopeRevision: bridgeProductNonnegativeSequenceSchema,
	subscriptionId: bridgeProductIdentifierSchema,
	subscriptionKind: bridgeProductMetadataApplicationKindSchema,
} as const;

const scopeSchema = z.object({ kind: z.string().min(1) }).catchall(z.unknown());

export const bridgeProductViewScopeRequestSchema = z
	.object({
		...viewControlShape,
		kind: z.literal('subscription.setScope'),
		scope: scopeSchema,
	})
	.strict();

export const bridgeProductViewResnapshotRequestSchema = z
	.object({
		...viewControlShape,
		kind: z.literal('subscription.resnapshot'),
	})
	.strict();

export const bridgeProductViewAcknowledgementRequestSchema = z
	.object({
		handle: bridgeProductIdentifierSchema,
		kind: z.literal('subscription.acknowledge'),
		paneSessionId: bridgeProductIdentifierSchema,
		receivedThroughDeliverySequence: bridgeProductPositiveSequenceSchema,
		subscriptionId: bridgeProductIdentifierSchema,
		wireVersion: z.literal(BRIDGE_PRODUCT_WIRE_VERSION),
		workerInstanceId: bridgeProductIdentifierSchema,
	})
	.strict();

export type BridgeProductViewScopeRequest = z.infer<typeof bridgeProductViewScopeRequestSchema>;
export type BridgeProductViewResnapshotRequest = z.infer<
	typeof bridgeProductViewResnapshotRequestSchema
>;
export type BridgeProductViewAcknowledgementRequest = z.infer<
	typeof bridgeProductViewAcknowledgementRequestSchema
>;
