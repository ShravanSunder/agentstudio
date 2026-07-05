import { z } from 'zod';

export const bridgeWorkerPierreRenderKindSchema = z.enum(['reviewDiff', 'fileText']);
export const bridgeWorkerPierreBudgetClassSchema = z.enum(['interactive', 'visible', 'background']);
export const bridgeWorkerDemandLaneSchema = z.enum([
	'selected',
	'visible',
	'nearby',
	'speculative',
	'background',
]);

export const bridgeWorkerDemandRankSchema = z
	.object({
		lane: bridgeWorkerDemandLaneSchema,
		priority: z.number().finite(),
	})
	.strict();

export const bridgeWorkerPierreRenderWindowSchema = z
	.object({
		startLine: z.number().int().nonnegative(),
		endLine: z.number().int().nonnegative(),
		totalLineCount: z.number().int().nonnegative(),
	})
	.strict();

export const bridgeWorkerPierreRenderPayloadSchema = z
	.object({
		kind: z.literal('textWindow'),
		textBytes: z.instanceof(ArrayBuffer),
	})
	.strict();

export const bridgeWorkerPierreRenderBudgetSchema = z
	.object({
		className: bridgeWorkerPierreBudgetClassSchema,
		maxBytes: z.number().int().nonnegative(),
		maxWindowLines: z.number().int().nonnegative(),
	})
	.strict();

export const bridgeWorkerPierreRenderJobPropsSchema = z
	.object({
		itemId: z.string().min(1),
		renderKind: bridgeWorkerPierreRenderKindSchema,
		contentCacheKey: z.string().min(1),
		contentHash: z.string().min(1),
		language: z.string().min(1),
		bridgeDemandRank: bridgeWorkerDemandRankSchema,
		window: bridgeWorkerPierreRenderWindowSchema,
		payload: bridgeWorkerPierreRenderPayloadSchema,
		budget: bridgeWorkerPierreRenderBudgetSchema,
	})
	.strict();

export const bridgeWorkerPierreRenderJobSchema = bridgeWorkerPierreRenderJobPropsSchema
	.extend({
		budgetClass: bridgeWorkerPierreBudgetClassSchema,
		payloadByteLength: z.number().int().nonnegative(),
		windowLineCount: z.number().int().nonnegative(),
	})
	.strict();

export type BridgeWorkerPierreRenderKind = z.infer<typeof bridgeWorkerPierreRenderKindSchema>;
export type BridgeWorkerPierreBudgetClass = z.infer<typeof bridgeWorkerPierreBudgetClassSchema>;
export type BridgeWorkerDemandLane = z.infer<typeof bridgeWorkerDemandLaneSchema>;
export type BridgeWorkerDemandRank = z.infer<typeof bridgeWorkerDemandRankSchema>;
export type BridgeWorkerPierreRenderWindow = z.infer<typeof bridgeWorkerPierreRenderWindowSchema>;
export type BridgeWorkerPierreRenderPayload = z.infer<typeof bridgeWorkerPierreRenderPayloadSchema>;
export type BridgeWorkerPierreRenderBudget = z.infer<typeof bridgeWorkerPierreRenderBudgetSchema>;
export type BuildBridgeWorkerPierreRenderJobProps = z.infer<
	typeof bridgeWorkerPierreRenderJobPropsSchema
>;
export type BridgeWorkerPierreRenderJob = z.infer<typeof bridgeWorkerPierreRenderJobSchema>;

export function buildBridgeWorkerPierreRenderJob(
	props: BuildBridgeWorkerPierreRenderJobProps,
): BridgeWorkerPierreRenderJob {
	const parsedProps = bridgeWorkerPierreRenderJobPropsSchema.parse(props);
	const payloadByteLength = parsedProps.payload.textBytes.byteLength;
	const windowLineCount = parsedProps.window.endLine - parsedProps.window.startLine + 1;
	if (windowLineCount < 0) {
		throw new Error('Bridge worker Pierre render job has an invalid line window.');
	}
	if (payloadByteLength > parsedProps.budget.maxBytes) {
		throw new Error(
			`Bridge worker Pierre render job exceeds byte budget: ${payloadByteLength} > ${parsedProps.budget.maxBytes}.`,
		);
	}
	if (windowLineCount > parsedProps.budget.maxWindowLines) {
		throw new Error(
			`Bridge worker Pierre render job exceeds line budget: ${windowLineCount} > ${parsedProps.budget.maxWindowLines}.`,
		);
	}

	return bridgeWorkerPierreRenderJobSchema.parse({
		...parsedProps,
		budgetClass: parsedProps.budget.className,
		payloadByteLength,
		windowLineCount,
	});
}
