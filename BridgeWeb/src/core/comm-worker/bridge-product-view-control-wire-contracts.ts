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
	domain: bridgeProductIdentifierSchema,
	handle: bridgeProductIdentifierSchema,
	incarnation: bridgeProductIdentifierSchema,
	scopeRevision: bridgeProductNonnegativeSequenceSchema,
	subscriptionId: bridgeProductIdentifierSchema,
	subscriptionKind: bridgeProductMetadataApplicationKindSchema,
} as const;

const fileChangeKindSchema = z.enum(['added', 'modified', 'renamed', 'deleted', 'copied']);
const fileChangeKindsSchema = z.array(fileChangeKindSchema).superRefine((kinds, context): void => {
	if (new Set(kinds).size !== kinds.length) {
		context.addIssue({ code: 'custom', message: 'File change kinds must be unique.' });
	}
});
const fileChangeFilterSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('none') }).strict(),
	z
		.object({
			baseline: z.discriminatedUnion('kind', [
				z.object({ kind: z.literal('uncommitted') }).strict(),
				z.object({ kind: z.literal('originDefaultMergeBase') }).strict(),
			]),
			kind: z.literal('changes'),
			kinds: fileChangeKindsSchema,
		})
		.strict(),
]);

export const bridgeProductViewScopeSchema = z
	.object({ kind: z.string().min(1) })
	.catchall(z.unknown())
	.superRefine((scope, context): void => {
		if (scope.kind !== 'file') return;
		if (!fileChangeFilterSchema.safeParse(scope['changeFilter']).success) {
			context.addIssue({ code: 'custom', message: 'Invalid File change filter.' });
		}
	});

export const bridgeProductViewScopeRequestSchema = z
	.object({
		...viewControlShape,
		kind: z.literal('subscription.setScope'),
		scope: bridgeProductViewScopeSchema,
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
		domain: bridgeProductIdentifierSchema,
		handle: bridgeProductIdentifierSchema,
		incarnation: bridgeProductIdentifierSchema,
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
