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

export const bridgeWorkerPierreTextWindowPayloadSchema = z
	.object({
		kind: z.literal('textWindow'),
		textBytes: z.instanceof(ArrayBuffer),
	})
	.strict();

export const bridgeWorkerPierreDiffTextWindowPayloadSchema = z
	.object({
		kind: z.literal('diffTextWindow'),
		baseTextBytes: z.instanceof(ArrayBuffer).nullable(),
		headTextBytes: z.instanceof(ArrayBuffer).nullable(),
	})
	.strict();

export const bridgeWorkerPierreRenderPayloadSchema = z.discriminatedUnion('kind', [
	bridgeWorkerPierreTextWindowPayloadSchema,
	bridgeWorkerPierreDiffTextWindowPayloadSchema,
]);

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
export type BridgeWorkerPierreTextWindowPayload = z.infer<
	typeof bridgeWorkerPierreTextWindowPayloadSchema
>;
export type BridgeWorkerPierreDiffTextWindowPayload = z.infer<
	typeof bridgeWorkerPierreDiffTextWindowPayloadSchema
>;
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
	assertBridgeWorkerPierreRenderPayloadMatchesKind(parsedProps);
	const payloadByteLength = bridgeWorkerPierreRenderPayloadByteLength(parsedProps.payload);
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

function assertBridgeWorkerPierreRenderPayloadMatchesKind(
	props: BuildBridgeWorkerPierreRenderJobProps,
): void {
	if (props.renderKind === 'reviewDiff') {
		if (props.payload.kind !== 'diffTextWindow') {
			throw new Error('Bridge worker review diff jobs require a diffTextWindow payload.');
		}
		if (props.payload.baseTextBytes === null && props.payload.headTextBytes === null) {
			throw new Error('Bridge worker review diff jobs require at least one text window side.');
		}
		return;
	}
	if (props.payload.kind !== 'textWindow') {
		throw new Error('Bridge worker file text jobs require a textWindow payload.');
	}
}

function bridgeWorkerPierreRenderPayloadByteLength(
	payload: BridgeWorkerPierreRenderPayload,
): number {
	switch (payload.kind) {
		case 'textWindow':
			return payload.textBytes.byteLength;
		case 'diffTextWindow':
			return (payload.baseTextBytes?.byteLength ?? 0) + (payload.headTextBytes?.byteLength ?? 0);
	}
	const exhaustivePayload: never = payload;
	void exhaustivePayload;
	throw new Error('Unhandled Bridge worker Pierre render payload kind.');
}
