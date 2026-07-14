import { z } from 'zod';

import {
	type BridgeProductAssert,
	bridgeProductIdentifierSchema,
	type BridgeProductRegistryValue,
	type BridgeProductTypeSetsEqual,
} from './bridge-product-contract-primitives.js';
import { bridgeProductFileSourceConfigurationSchema } from './bridge-product-subscription-contracts.js';

export const bridgeProductFileSourceCurrentRequestSchema = z.object({}).strict();
export const bridgeProductFileSourceCurrentResultSchema = z.discriminatedUnion('status', [
	z
		.object({
			source: bridgeProductFileSourceConfigurationSchema,
			status: z.literal('available'),
		})
		.strict(),
	z
		.object({
			reason: z.literal('no-file-source-authority'),
			status: z.literal('unavailable'),
		})
		.strict(),
]);

export const bridgeProductReviewMarkFileViewedRequestSchema = z
	.object({ itemId: bridgeProductIdentifierSchema })
	.strict();
export const bridgeProductReviewMarkFileViewedResultSchema = z.null();
export const bridgeProductReviewIntakeReadyRequestSchema = z
	.object({
		reason: bridgeProductIdentifierSchema.nullable(),
		streamId: bridgeProductIdentifierSchema.nullable(),
	})
	.strict();
export const bridgeProductReviewIntakeReadyResultSchema = z.null();

const bridgeProductActiveViewerSourceBaseSchema = z
	.object({
		generation: z.number().int().nonnegative(),
		streamId: bridgeProductIdentifierSchema,
	})
	.strict();

export const bridgeProductReviewActiveViewerModeUpdateRequestSchema = z
	.object({
		activeSource: bridgeProductActiveViewerSourceBaseSchema.nullable(),
		sequence: z.number().int().positive(),
		sessionId: bridgeProductIdentifierSchema,
	})
	.strict();
export const bridgeProductFileActiveViewerModeUpdateRequestSchema = z
	.object({
		activeSource: bridgeProductActiveViewerSourceBaseSchema.nullable(),
		sequence: z.number().int().positive(),
		sessionId: bridgeProductIdentifierSchema,
	})
	.strict();
export const bridgeProductActiveViewerModeUpdateResultSchema = z.null();

export type BridgeProductCallRegistry = {
	readonly 'file.source.current': {
		readonly request: z.infer<typeof bridgeProductFileSourceCurrentRequestSchema>;
		readonly result: z.infer<typeof bridgeProductFileSourceCurrentResultSchema>;
		readonly surface: 'file';
	};
	readonly 'file.activeViewerMode.update': {
		readonly request: z.infer<typeof bridgeProductFileActiveViewerModeUpdateRequestSchema>;
		readonly result: z.infer<typeof bridgeProductActiveViewerModeUpdateResultSchema>;
		readonly surface: 'file';
	};
	readonly 'review.markFileViewed': {
		readonly request: z.infer<typeof bridgeProductReviewMarkFileViewedRequestSchema>;
		readonly result: z.infer<typeof bridgeProductReviewMarkFileViewedResultSchema>;
		readonly surface: 'review';
	};
	readonly 'review.intake.ready': {
		readonly request: z.infer<typeof bridgeProductReviewIntakeReadyRequestSchema>;
		readonly result: z.infer<typeof bridgeProductReviewIntakeReadyResultSchema>;
		readonly surface: 'review';
	};
	readonly 'review.activeViewerMode.update': {
		readonly request: z.infer<typeof bridgeProductReviewActiveViewerModeUpdateRequestSchema>;
		readonly result: z.infer<typeof bridgeProductActiveViewerModeUpdateResultSchema>;
		readonly surface: 'review';
	};
};

export type BridgeProductCallKind = keyof BridgeProductCallRegistry;
export type BridgeProductCallRequest<TCallKind extends BridgeProductCallKind> =
	BridgeProductRegistryValue<BridgeProductCallRegistry, TCallKind, 'request'>;
export type BridgeProductCallResult<TCallKind extends BridgeProductCallKind> =
	BridgeProductRegistryValue<BridgeProductCallRegistry, TCallKind, 'result'>;

const bridgeProductSurfaceByCallKind = {
	'file.activeViewerMode.update': 'file',
	'file.source.current': 'file',
	'review.activeViewerMode.update': 'review',
	'review.intake.ready': 'review',
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
			method: z.literal('file.source.current'),
			request: bridgeProductFileSourceCurrentRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.activeViewerMode.update'),
			request: bridgeProductFileActiveViewerModeUpdateRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.activeViewerMode.update'),
			request: bridgeProductReviewActiveViewerModeUpdateRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.markFileViewed'),
			request: bridgeProductReviewMarkFileViewedRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.intake.ready'),
			request: bridgeProductReviewIntakeReadyRequestSchema,
		})
		.strict(),
]);

export const bridgeProductCallResultSchema = z.discriminatedUnion('method', [
	z
		.object({
			method: z.literal('file.source.current'),
			result: bridgeProductFileSourceCurrentResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.activeViewerMode.update'),
			result: bridgeProductActiveViewerModeUpdateResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.activeViewerMode.update'),
			result: bridgeProductActiveViewerModeUpdateResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.markFileViewed'),
			result: bridgeProductReviewMarkFileViewedResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.intake.ready'),
			result: bridgeProductReviewIntakeReadyResultSchema,
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
