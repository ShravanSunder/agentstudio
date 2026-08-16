import { z } from 'zod';

export const bridgeMarkdownRenderWorkerMethodSchema = z.literal('markdown.render');

export const bridgeMarkdownFileSourceIdentitySchema = z.object({
	surface: z.literal('file'),
	sourceId: z.string().min(1),
	sourceGeneration: z.number().int().nonnegative(),
	fileId: z.string().min(1),
	fileVersion: z.number().int().nonnegative(),
});

export const bridgeMarkdownSourceIdentitySchema = bridgeMarkdownFileSourceIdentitySchema;

export type BridgeMarkdownSourceIdentity = z.infer<typeof bridgeMarkdownSourceIdentitySchema>;

export const bridgeMarkdownRenderRequestIdentitySchema = z.object({
	requestId: z.string().min(1),
	sourceIdentity: bridgeMarkdownSourceIdentitySchema,
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

export const bridgeMarkdownMermaidDiagramSchema = z.object({
	id: z.string().min(1),
	source: z.string(),
});

export type BridgeMarkdownMermaidDiagram = z.infer<typeof bridgeMarkdownMermaidDiagramSchema>;

export const bridgeMarkdownRenderWorkerMetricsSchema = z.object({
	durationMilliseconds: z.number().nonnegative(),
	inputBytes: z.number().int().nonnegative(),
	outputBytes: z.number().int().nonnegative(),
	mermaidDiagramCount: z.number().int().nonnegative(),
});

export type BridgeMarkdownRenderWorkerMetrics = z.infer<
	typeof bridgeMarkdownRenderWorkerMetricsSchema
>;

export const bridgeMarkdownRenderWorkerSuccessResponseSchema =
	bridgeMarkdownRenderRequestIdentitySchema.extend({
		schemaVersion: z.literal(1),
		method: bridgeMarkdownRenderWorkerMethodSchema,
		ok: z.literal(true),
		htmlCandidate: z.string(),
		mermaidDiagrams: z.array(bridgeMarkdownMermaidDiagramSchema),
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
		sourceIdentity: request.sourceIdentity,
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
		JSON.stringify(left.sourceIdentity) === JSON.stringify(right.sourceIdentity) &&
		left.contentCacheKey === right.contentCacheKey &&
		left.contentHash === right.contentHash &&
		left.abortKey === right.abortKey
	);
}
