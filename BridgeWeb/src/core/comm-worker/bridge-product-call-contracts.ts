import { z } from 'zod';

import {
	type BridgeProductAssert,
	bridgeProductIdentifierSchema,
	type BridgeProductRegistryValue,
	type BridgeProductTypeSetsEqual,
} from './bridge-product-contract-primitives.js';

export const bridgeProductReviewMarkFileViewedRequestSchema = z
	.object({ itemId: bridgeProductIdentifierSchema })
	.strict();
export const bridgeProductReviewMarkFileViewedResultSchema = z.null();

export type BridgeProductCallRegistry = {
	readonly 'review.markFileViewed': {
		readonly request: z.infer<typeof bridgeProductReviewMarkFileViewedRequestSchema>;
		readonly result: z.infer<typeof bridgeProductReviewMarkFileViewedResultSchema>;
		readonly surface: 'review';
	};
};

export type BridgeProductCallKind = keyof BridgeProductCallRegistry;
export type BridgeProductCallRequest<TCallKind extends BridgeProductCallKind> =
	BridgeProductRegistryValue<BridgeProductCallRegistry, TCallKind, 'request'>;
export type BridgeProductCallResult<TCallKind extends BridgeProductCallKind> =
	BridgeProductRegistryValue<BridgeProductCallRegistry, TCallKind, 'result'>;

const bridgeProductSurfaceByCallKind = {
	'review.markFileViewed': 'review',
} as const satisfies {
	readonly [TCallKind in BridgeProductCallKind]: BridgeProductCallRegistry[TCallKind]['surface'];
};

export function bridgeProductSurfaceForCallKind<TCallKind extends BridgeProductCallKind>(
	callKind: TCallKind,
): BridgeProductCallRegistry[TCallKind]['surface'] {
	return bridgeProductSurfaceByCallKind[callKind];
}

export const bridgeProductCallRequestSchema = z.discriminatedUnion('method', [
	z
		.object({
			method: z.literal('review.markFileViewed'),
			request: bridgeProductReviewMarkFileViewedRequestSchema,
		})
		.strict(),
]);

export const bridgeProductCallResultSchema = z.discriminatedUnion('method', [
	z
		.object({
			method: z.literal('review.markFileViewed'),
			result: bridgeProductReviewMarkFileViewedResultSchema,
		})
		.strict(),
]);

export type BridgeProductCallRequestWire = z.infer<typeof bridgeProductCallRequestSchema>;
export type BridgeProductCallResultWire = z.infer<typeof bridgeProductCallResultSchema>;
export type BridgeProductCallRequestRegistryParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<BridgeProductCallRequestWire['method'], BridgeProductCallKind>
>;
export type BridgeProductCallResultRegistryParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<BridgeProductCallResultWire['method'], BridgeProductCallKind>
>;
