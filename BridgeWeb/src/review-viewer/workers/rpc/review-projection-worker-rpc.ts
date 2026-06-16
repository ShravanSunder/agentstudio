import { z } from 'zod';

import {
	bridgeReviewProjectionInputSchema,
	bridgeReviewProjectionRequestIdentitySchema,
	bridgeReviewProjectionRequestSchema,
	bridgeReviewProjectionSchema,
	bridgeReviewProjectionWorkloadIdSchema,
	type BridgeReviewProjection,
	type BridgeReviewProjectionRequest,
	type BridgeReviewProjectionRequestIdentity,
} from '../../models/review-projection-models.js';
import { buildBridgeReviewProjectionFromInput } from '../../navigation/review-projection.js';

export const bridgeReviewProjectionWorkerMethodSchema = z.literal('reviewProjection.build');

export const bridgeReviewProjectionWorkerRequestSchema =
	bridgeReviewProjectionRequestIdentitySchema.extend({
		schemaVersion: z.literal(1),
		method: bridgeReviewProjectionWorkerMethodSchema,
		projectionRequest: bridgeReviewProjectionRequestSchema,
		projectionInput: bridgeReviewProjectionInputSchema,
		visibleItemIds: z.array(z.string().min(1)).readonly(),
		workloadId: bridgeReviewProjectionWorkloadIdSchema,
	});

export type BridgeReviewProjectionWorkerRequest = z.infer<
	typeof bridgeReviewProjectionWorkerRequestSchema
>;

export const bridgeReviewProjectionWorkerMetricsSchema = z.object({
	durationMilliseconds: z.number().nonnegative(),
	inputItemCount: z.number().int().nonnegative(),
	outputItemCount: z.number().int().nonnegative(),
	treePathCount: z.number().int().nonnegative(),
});

export type BridgeReviewProjectionWorkerMetrics = z.infer<
	typeof bridgeReviewProjectionWorkerMetricsSchema
>;

export const bridgeReviewProjectionWorkerSuccessResponseSchema =
	bridgeReviewProjectionRequestIdentitySchema.extend({
		schemaVersion: z.literal(1),
		method: bridgeReviewProjectionWorkerMethodSchema,
		ok: z.literal(true),
		result: bridgeReviewProjectionSchema,
		metrics: bridgeReviewProjectionWorkerMetricsSchema,
	});

export type BridgeReviewProjectionWorkerSuccessResponse = z.infer<
	typeof bridgeReviewProjectionWorkerSuccessResponseSchema
>;

export const bridgeReviewProjectionWorkerFailureResponseSchema =
	bridgeReviewProjectionRequestIdentitySchema.extend({
		schemaVersion: z.literal(1),
		method: bridgeReviewProjectionWorkerMethodSchema,
		ok: z.literal(false),
		error: z.object({
			code: z.enum(['invalidRequest', 'projectionFailed', 'aborted']),
			message: z.string().min(1),
		}),
	});

export type BridgeReviewProjectionWorkerFailureResponse = z.infer<
	typeof bridgeReviewProjectionWorkerFailureResponseSchema
>;

export const bridgeReviewProjectionWorkerResponseSchema = z.discriminatedUnion('ok', [
	bridgeReviewProjectionWorkerSuccessResponseSchema,
	bridgeReviewProjectionWorkerFailureResponseSchema,
]);

export type BridgeReviewProjectionWorkerResponse = z.infer<
	typeof bridgeReviewProjectionWorkerResponseSchema
>;

export interface BuildBridgeReviewProjectionWorkerSuccessResponseProps {
	readonly request: BridgeReviewProjectionWorkerRequest;
	readonly durationMilliseconds: number;
}

export type BridgeReviewProjectionWorkerResult = BridgeReviewProjection;

export function buildBridgeReviewProjectionWorkerSuccessResponse(
	props: BuildBridgeReviewProjectionWorkerSuccessResponseProps,
): BridgeReviewProjectionWorkerSuccessResponse {
	const result = buildBridgeReviewProjectionFromInput({
		projectionInput: props.request.projectionInput,
		request: props.request.projectionRequest,
	});
	const response = {
		schemaVersion: 1,
		method: props.request.method,
		ok: true,
		...identityFromWorkerRequest(props.request),
		result,
		metrics: {
			durationMilliseconds: props.durationMilliseconds,
			inputItemCount: props.request.projectionInput.orderedItems.length,
			outputItemCount: result.orderedItemIds.length,
			treePathCount: result.orderedPaths.length,
		},
	} satisfies BridgeReviewProjectionWorkerSuccessResponse;

	return bridgeReviewProjectionWorkerSuccessResponseSchema.parse(response);
}

export function identityFromWorkerRequest(
	request: BridgeReviewProjectionWorkerRequest,
): BridgeReviewProjectionRequestIdentity {
	return {
		requestId: request.requestId,
		packageId: request.packageId,
		reviewGeneration: request.reviewGeneration,
		revision: request.revision,
		projectionRequestFingerprint: request.projectionRequestFingerprint,
		...(request.abortKey === undefined ? {} : { abortKey: request.abortKey }),
	};
}

export function fingerprintBridgeReviewProjectionRequest(
	request: BridgeReviewProjectionRequest,
): string {
	return `review-projection:${stableStringifyBridgeValue(
		bridgeReviewProjectionRequestSchema.parse(request),
	)}`;
}

export function identitiesMatch(
	left: BridgeReviewProjectionRequestIdentity | null,
	right: BridgeReviewProjectionRequestIdentity,
): boolean {
	return (
		left !== null &&
		left.requestId === right.requestId &&
		left.packageId === right.packageId &&
		left.reviewGeneration === right.reviewGeneration &&
		left.revision === right.revision &&
		left.projectionRequestFingerprint === right.projectionRequestFingerprint &&
		left.abortKey === right.abortKey
	);
}

function stableStringifyBridgeValue(value: unknown): string {
	if (Array.isArray(value)) {
		return `[${value.map((item: unknown): string => stableStringifyBridgeValue(item)).join(',')}]`;
	}
	if (typeof value === 'object' && value !== null) {
		const sortedEntries = Object.entries(value);
		// oxlint-disable-next-line unicorn/no-array-sort -- WebKit engines older than Safari 16.4 do not support Array#toSorted.
		sortedEntries.sort(([leftKey], [rightKey]): number => leftKey.localeCompare(rightKey));
		const entries = sortedEntries.map(
			([key, entryValue]: readonly [string, unknown]): string =>
				`${JSON.stringify(key)}:${stableStringifyBridgeValue(entryValue)}`,
		);
		return `{${entries.join(',')}}`;
	}
	return JSON.stringify(value);
}
