import { z } from 'zod';

import { bridgeProductReviewComparisonTargetSchema } from './bridge-product-call-contracts.js';
import { bridgeProductWorktreeAnnotationOperationSchema } from './bridge-product-call-contracts.js';

export const bridgeActiveViewerSourceSchema = z
	.object({
		protocol: z.enum(['review', 'worktree-file']),
		streamId: z.string().min(1),
		generation: z.number().int().nonnegative(),
	})
	.strict();

export const bridgeActiveViewerModeUpdateSchema = z
	.object({
		sessionId: z.string().min(1),
		sequence: z.number().int().positive(),
		mode: z.enum(['file', 'review']),
		activeSource: bridgeActiveViewerSourceSchema.nullable(),
		nativeSelectionRequestId: z.string().min(1).nullable(),
	})
	.strict();

export const bridgeProductControlIntakeReadyParamsSchema = z
	.object({
		protocolId: z.enum(['review', 'worktree-file']),
		streamId: z.string().min(1).nullable().optional(),
		generation: z.number().int().nonnegative().optional(),
		reason: z.string().min(1).nullable().optional(),
	})
	.strict();

const bridgeProductControlMarkFileViewedCommandSchema = z
	.object({
		method: z.literal('review.markFileViewed'),
		params: z.object({ fileId: z.string().min(1) }).strict(),
	})
	.strict();

const bridgeProductControlWorktreeAnnotationCommandSchema = z
	.object({
		method: z.enum(['file.annotations.command', 'review.annotations.command']),
		params: z.object({ operation: bridgeProductWorktreeAnnotationOperationSchema }).strict(),
	})
	.strict();

const bridgeProductControlActiveViewerModeUpdateCommandSchema = z
	.object({
		method: z.literal('bridge.activeViewerMode.update'),
		params: bridgeActiveViewerModeUpdateSchema,
	})
	.strict();

const bridgeProductControlReviewComparisonUpdateCommandSchema = z
	.object({
		method: z.literal('review.comparison.update'),
		params: z.object({ target: bridgeProductReviewComparisonTargetSchema }).strict(),
	})
	.strict();

const bridgeProductControlFileRefreshRetryCommandSchema = z
	.object({
		method: z.literal('file.refresh.retry'),
		params: z.object({}).strict(),
	})
	.strict();

const bridgeProductControlReviewComparisonTargetsQueryCommandSchema = z
	.object({
		method: z.literal('review.comparisonTargets.query'),
		params: z.object({}).strict(),
	})
	.strict();

const bridgeProductControlIntakeReadyCommandSchema = z
	.object({
		method: z.literal('bridge.intakeReady'),
		params: bridgeProductControlIntakeReadyParamsSchema,
	})
	.strict();

export const bridgeProductControlCommandSchema = z.discriminatedUnion('method', [
	bridgeProductControlFileRefreshRetryCommandSchema,
	bridgeProductControlWorktreeAnnotationCommandSchema,
	bridgeProductControlMarkFileViewedCommandSchema,
	bridgeProductControlReviewComparisonUpdateCommandSchema,
	bridgeProductControlReviewComparisonTargetsQueryCommandSchema,
	bridgeProductControlActiveViewerModeUpdateCommandSchema,
	bridgeProductControlIntakeReadyCommandSchema,
]);

export type BridgeActiveViewerSource = z.infer<typeof bridgeActiveViewerSourceSchema>;
export type BridgeActiveViewerModeUpdate = z.infer<typeof bridgeActiveViewerModeUpdateSchema>;
export type BridgeProductControlCommand = z.infer<typeof bridgeProductControlCommandSchema>;
