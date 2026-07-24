import { z } from 'zod';

import {
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductSha256Schema,
} from './bridge-product-contract-primitives.js';

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

const bridgeWorkerCodeViewContentStateSchema = z.enum([
	'placeholder',
	'loading',
	'hydrated',
	'windowed',
]);

const bridgeWorkerCodeViewContentRoleSchema = z.enum(['base', 'head', 'diff', 'file']);

export const bridgeWorkerRenderSourceCorrelationSchema = z
	.object({
		descriptorId: bridgeProductIdentifierSchema,
		itemId: z.string().min(1),
		observedSha256: bridgeProductSha256Schema,
		position: z.string().min(1).max(256),
		requestId: bridgeProductIdentifierSchema,
		role: bridgeWorkerCodeViewContentRoleSchema,
		sourceGeneration: bridgeProductNonnegativeSequenceSchema,
		sourceIdentity: bridgeProductIdentifierSchema,
	})
	.strict();

const bridgeWorkerPierreFileContentsSchema = z
	.object({
		name: z.string().min(1),
		contents: z.string(),
		lang: z.string().min(1).optional(),
		header: z.string().optional(),
		cacheKey: z.string().min(1).optional(),
		bridgeDemandRank: z.number().finite().optional(),
	})
	.strict();

const bridgeWorkerPierreContextContentSchema = z
	.object({
		type: z.literal('context'),
		lines: z.number().int().nonnegative(),
		additionLineIndex: z.number().int(),
		deletionLineIndex: z.number().int(),
	})
	.strict();

const bridgeWorkerPierreChangeContentSchema = z
	.object({
		type: z.literal('change'),
		deletions: z.number().int().nonnegative(),
		deletionLineIndex: z.number().int(),
		additions: z.number().int().nonnegative(),
		additionLineIndex: z.number().int(),
	})
	.strict();

const bridgeWorkerPierreHunkSchema = z
	.object({
		collapsedBefore: z.number().int().nonnegative(),
		additionStart: z.number().int().nonnegative(),
		additionCount: z.number().int().nonnegative(),
		additionLines: z.number().int().nonnegative(),
		additionLineIndex: z.number().int(),
		deletionStart: z.number().int().nonnegative(),
		deletionCount: z.number().int().nonnegative(),
		deletionLines: z.number().int().nonnegative(),
		deletionLineIndex: z.number().int(),
		hunkContent: z
			.array(
				z.discriminatedUnion('type', [
					bridgeWorkerPierreContextContentSchema,
					bridgeWorkerPierreChangeContentSchema,
				]),
			)
			.readonly(),
		hunkContext: z.string().optional(),
		hunkSpecs: z.string().optional(),
		splitLineStart: z.number().int().nonnegative(),
		splitLineCount: z.number().int().nonnegative(),
		unifiedLineStart: z.number().int().nonnegative(),
		unifiedLineCount: z.number().int().nonnegative(),
		noEOFCRDeletions: z.boolean(),
		noEOFCRAdditions: z.boolean(),
	})
	.strict();

const bridgeWorkerPierreFileDiffMetadataSchema = z
	.object({
		name: z.string().min(1),
		prevName: z.string().min(1).optional(),
		lang: z.string().min(1).optional(),
		newObjectId: z.string().min(1).optional(),
		prevObjectId: z.string().min(1).optional(),
		mode: z.string().min(1).optional(),
		prevMode: z.string().min(1).optional(),
		type: z.enum(['change', 'rename-pure', 'rename-changed', 'new', 'deleted']),
		hunks: z.array(bridgeWorkerPierreHunkSchema).readonly(),
		splitLineCount: z.number().int().nonnegative(),
		unifiedLineCount: z.number().int().nonnegative(),
		isPartial: z.boolean(),
		deletionLines: z.array(z.string()).readonly(),
		additionLines: z.array(z.string()).readonly(),
		cacheKey: z.string().min(1).optional(),
		bridgeDemandRank: z.number().finite().optional(),
	})
	.strict();

const bridgeWorkerCodeViewItemMetadataSchema = z
	.object({
		itemId: z.string().min(1),
		displayPath: z.string().min(1),
		contentState: bridgeWorkerCodeViewContentStateSchema,
		contentRoles: z.array(bridgeWorkerCodeViewContentRoleSchema).readonly(),
		cacheKey: z.string().min(1),
		lineCount: z.number().int().nonnegative().nullable(),
	})
	.strict();

export const bridgeWorkerCodeViewFileItemSchema = z
	.object({
		id: z.string().min(1),
		type: z.literal('file'),
		file: bridgeWorkerPierreFileContentsSchema,
		version: z.number().int().nonnegative().optional(),
		collapsed: z.boolean().optional(),
		bridgeMetadata: bridgeWorkerCodeViewItemMetadataSchema,
	})
	.strict();

export const bridgeWorkerCodeViewDiffItemSchema = z
	.object({
		id: z.string().min(1),
		type: z.literal('diff'),
		fileDiff: bridgeWorkerPierreFileDiffMetadataSchema,
		version: z.number().int().nonnegative().optional(),
		collapsed: z.boolean().optional(),
		bridgeMetadata: bridgeWorkerCodeViewItemMetadataSchema,
	})
	.strict();

export const bridgeWorkerPierreCodeViewFileItemPayloadSchema = z
	.object({
		kind: z.literal('codeViewFileItem'),
		item: bridgeWorkerCodeViewFileItemSchema,
	})
	.strict();

export const bridgeWorkerPierreCodeViewDiffItemPayloadSchema = z
	.object({
		kind: z.literal('codeViewDiffItem'),
		item: bridgeWorkerCodeViewDiffItemSchema,
	})
	.strict();

export const bridgeWorkerPierreRenderPayloadSchema = z.discriminatedUnion('kind', [
	bridgeWorkerPierreCodeViewFileItemPayloadSchema,
	bridgeWorkerPierreCodeViewDiffItemPayloadSchema,
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
		sourceCorrelations: z
			.array(bridgeWorkerRenderSourceCorrelationSchema)
			.max(4)
			.readonly()
			.optional(),
	})
	.strict();

export const bridgeWorkerPierreRenderJobSchema = bridgeWorkerPierreRenderJobPropsSchema
	.extend({
		budgetClass: bridgeWorkerPierreBudgetClassSchema,
		payloadByteLength: z.number().int().nonnegative(),
		sourceCorrelations: z.array(bridgeWorkerRenderSourceCorrelationSchema).max(4).readonly(),
		windowLineCount: z.number().int().nonnegative(),
	})
	.strict();

export type BridgeWorkerPierreRenderKind = z.infer<typeof bridgeWorkerPierreRenderKindSchema>;
export type BridgeWorkerPierreBudgetClass = z.infer<typeof bridgeWorkerPierreBudgetClassSchema>;
export type BridgeWorkerDemandLane = z.infer<typeof bridgeWorkerDemandLaneSchema>;
export type BridgeWorkerDemandRank = z.infer<typeof bridgeWorkerDemandRankSchema>;
export type BridgeWorkerPierreRenderWindow = z.infer<typeof bridgeWorkerPierreRenderWindowSchema>;
export type BridgeWorkerCodeViewFileItem = z.infer<typeof bridgeWorkerCodeViewFileItemSchema>;
export type BridgeWorkerCodeViewDiffItem = z.infer<typeof bridgeWorkerCodeViewDiffItemSchema>;
export type BridgeWorkerPierreCodeViewFileItemPayload = z.infer<
	typeof bridgeWorkerPierreCodeViewFileItemPayloadSchema
>;
export type BridgeWorkerPierreCodeViewDiffItemPayload = z.infer<
	typeof bridgeWorkerPierreCodeViewDiffItemPayloadSchema
>;
export type BridgeWorkerPierreRenderPayload = z.infer<typeof bridgeWorkerPierreRenderPayloadSchema>;
export type BridgeWorkerPierreRenderBudget = z.infer<typeof bridgeWorkerPierreRenderBudgetSchema>;
export type BridgeWorkerRenderSourceCorrelation = z.infer<
	typeof bridgeWorkerRenderSourceCorrelationSchema
>;
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
		sourceCorrelations: parsedProps.sourceCorrelations ?? [],
		windowLineCount,
	});
}

function assertBridgeWorkerPierreRenderPayloadMatchesKind(
	props: BuildBridgeWorkerPierreRenderJobProps,
): void {
	if (props.renderKind === 'reviewDiff') {
		if (props.payload.kind !== 'codeViewDiffItem') {
			throw new Error('Bridge worker review diff jobs require a codeViewDiffItem payload.');
		}
		return;
	}
	if (props.payload.kind !== 'codeViewFileItem') {
		throw new Error('Bridge worker file text jobs require a codeViewFileItem payload.');
	}
}

export function bridgeWorkerPierreRenderPayloadByteLength(
	payload: BridgeWorkerPierreRenderPayload,
): number {
	switch (payload.kind) {
		case 'codeViewFileItem':
			return bridgeWorkerStringByteLength(payload.item.file.contents);
		case 'codeViewDiffItem':
			return (
				bridgeWorkerStringArrayByteLength(payload.item.fileDiff.deletionLines) +
				bridgeWorkerStringArrayByteLength(payload.item.fileDiff.additionLines)
			);
	}
	const exhaustivePayload: never = payload;
	void exhaustivePayload;
	throw new Error('Unhandled Bridge worker Pierre render payload kind.');
}

function bridgeWorkerStringArrayByteLength(values: readonly string[]): number {
	return values.reduce(
		(totalByteLength, value): number => totalByteLength + bridgeWorkerStringByteLength(value),
		0,
	);
}

function bridgeWorkerStringByteLength(value: string): number {
	return new TextEncoder().encode(value).byteLength;
}
