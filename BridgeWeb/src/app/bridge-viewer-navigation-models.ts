import { z } from 'zod';

export const bridgeViewerContextSchema = z.enum(['files', 'review']);
export type BridgeViewerContext = z.infer<typeof bridgeViewerContextSchema>;

export const bridgeViewerFileVersionSchema = z.enum(['base', 'head', 'current']);
export type BridgeViewerFileVersion = z.infer<typeof bridgeViewerFileVersionSchema>;

export const bridgeViewerFixtureSourceSchema = z
	.object({
		sourceKind: z.literal('fixture'),
		sourceId: z.string().min(1),
	})
	.strict();

export const bridgeViewerWorktreeSourceSchema = z
	.object({
		sourceKind: z.literal('worktree'),
		sourceId: z.string().min(1),
	})
	.strict();

export const bridgeViewerReviewComparisonSourceSchema = z
	.object({
		sourceKind: z.literal('reviewComparison'),
		sourceId: z.string().min(1),
		comparisonId: z.string().min(1),
	})
	.strict();

export const bridgeViewerSourceSchema = z.discriminatedUnion('sourceKind', [
	bridgeViewerFixtureSourceSchema,
	bridgeViewerWorktreeSourceSchema,
	bridgeViewerReviewComparisonSourceSchema,
]);
export type BridgeViewerSource = z.infer<typeof bridgeViewerSourceSchema>;

export const bridgeViewerFileRefSchema = z
	.object({
		sourceId: z.string().min(1),
		path: z.string().min(1),
	})
	.strict();
export type BridgeViewerFileRef = z.infer<typeof bridgeViewerFileRefSchema>;

export const bridgeViewerFileTargetSchema = z
	.object({
		targetKind: z.literal('file'),
		fileRef: bridgeViewerFileRefSchema,
		version: bridgeViewerFileVersionSchema,
		comparisonId: z.string().min(1).optional(),
	})
	.strict();

export const bridgeViewerDiffTargetSchema = z
	.object({
		targetKind: z.literal('diff'),
		comparisonId: z.string().min(1),
		reviewItemId: z.string().min(1).optional(),
		fileRef: bridgeViewerFileRefSchema.optional(),
	})
	.strict();

export const bridgeViewerTargetSchema = z.discriminatedUnion('targetKind', [
	bridgeViewerFileTargetSchema,
	bridgeViewerDiffTargetSchema,
]);
export type BridgeViewerTarget = z.infer<typeof bridgeViewerTargetSchema>;

export const bridgeViewerNavigationCommandSchema = z
	.object({
		commandId: z.string().min(1),
		commandKind: z.enum(['initialize', 'activateContext', 'activateTarget']),
		context: bridgeViewerContextSchema,
		source: bridgeViewerSourceSchema,
		target: bridgeViewerTargetSchema.optional(),
		restoreMemory: z.boolean(),
	})
	.strict();

export type BridgeViewerNavigationCommand = z.infer<typeof bridgeViewerNavigationCommandSchema>;
