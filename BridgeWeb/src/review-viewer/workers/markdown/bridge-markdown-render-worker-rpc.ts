import { z } from 'zod';

export const bridgeMarkdownRenderWorkerMethodSchema = z.literal('markdown.render');

export const bridgeMarkdownRenderRequestIdentitySchema = z.object({
	requestId: z.string().min(1),
	packageId: z.string().min(1),
	reviewGeneration: z.number().int().nonnegative(),
	revision: z.number().int().nonnegative(),
	itemId: z.string().min(1),
	itemVersion: z.number().int().nonnegative(),
	contentCacheKey: z.string().min(1),
	contentHash: z.string().min(1),
	abortKey: z.string().min(1).optional(),
});

export type BridgeMarkdownRenderRequestIdentity = z.infer<
	typeof bridgeMarkdownRenderRequestIdentitySchema
>;

export const bridgeMarkdownRenderWorkerAbortRequestSchema =
	bridgeMarkdownRenderRequestIdentitySchema.required({ abortKey: true }).extend({
		schemaVersion: z.literal(1),
		method: z.literal('markdown.render.abort'),
	});

export type BridgeMarkdownRenderWorkerAbortRequest = z.infer<
	typeof bridgeMarkdownRenderWorkerAbortRequestSchema
>;

export const bridgeMarkdownRenderWorkerRequestSchema =
	bridgeMarkdownRenderRequestIdentitySchema.extend({
		schemaVersion: z.literal(1),
		method: bridgeMarkdownRenderWorkerMethodSchema,
		markdownText: z.string(),
		sourcePath: z.string().min(1),
	});

export type BridgeMarkdownRenderWorkerRequest = z.infer<
	typeof bridgeMarkdownRenderWorkerRequestSchema
>;

export const bridgeMarkdownRenderWorkerMetricsSchema = z.object({
	durationMilliseconds: z.number().nonnegative(),
	inputBytes: z.number().int().nonnegative(),
	outputBytes: z.number().int().nonnegative(),
});

export type BridgeMarkdownRenderWorkerMetrics = z.infer<
	typeof bridgeMarkdownRenderWorkerMetricsSchema
>;

export const bridgeMarkdownRenderWorkerSuccessResponseSchema =
	bridgeMarkdownRenderRequestIdentitySchema.extend({
		schemaVersion: z.literal(1),
		method: bridgeMarkdownRenderWorkerMethodSchema,
		ok: z.literal(true),
		html: z.string(),
		metrics: bridgeMarkdownRenderWorkerMetricsSchema,
	});

export type BridgeMarkdownRenderWorkerSuccessResponse = z.infer<
	typeof bridgeMarkdownRenderWorkerSuccessResponseSchema
>;

export const bridgeMarkdownRenderWorkerFailureResponseSchema =
	bridgeMarkdownRenderRequestIdentitySchema.extend({
		schemaVersion: z.literal(1),
		method: bridgeMarkdownRenderWorkerMethodSchema,
		ok: z.literal(false),
		error: z.object({
			code: z.enum(['invalidRequest', 'renderFailed', 'aborted', 'transportFailed']),
			message: z.string().min(1),
		}),
	});

export type BridgeMarkdownRenderWorkerFailureResponse = z.infer<
	typeof bridgeMarkdownRenderWorkerFailureResponseSchema
>;

export const bridgeMarkdownRenderWorkerResponseSchema = z.discriminatedUnion('ok', [
	bridgeMarkdownRenderWorkerSuccessResponseSchema,
	bridgeMarkdownRenderWorkerFailureResponseSchema,
]);

export type BridgeMarkdownRenderWorkerResponse = z.infer<
	typeof bridgeMarkdownRenderWorkerResponseSchema
>;

export function identityFromMarkdownRenderWorkerRequest(
	request: BridgeMarkdownRenderWorkerRequest,
): BridgeMarkdownRenderRequestIdentity {
	return {
		requestId: request.requestId,
		packageId: request.packageId,
		reviewGeneration: request.reviewGeneration,
		revision: request.revision,
		itemId: request.itemId,
		itemVersion: request.itemVersion,
		contentCacheKey: request.contentCacheKey,
		contentHash: request.contentHash,
		...(request.abortKey === undefined ? {} : { abortKey: request.abortKey }),
	};
}

export function markdownRenderIdentitiesMatch(
	left: BridgeMarkdownRenderRequestIdentity | null,
	right: BridgeMarkdownRenderRequestIdentity,
): boolean {
	return (
		left !== null &&
		left.requestId === right.requestId &&
		left.packageId === right.packageId &&
		left.reviewGeneration === right.reviewGeneration &&
		left.revision === right.revision &&
		left.itemId === right.itemId &&
		left.itemVersion === right.itemVersion &&
		left.contentCacheKey === right.contentCacheKey &&
		left.contentHash === right.contentHash &&
		left.abortKey === right.abortKey
	);
}
