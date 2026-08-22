import { z } from 'zod';

import { bridgeProductReviewComparisonTargetSchema } from './bridge-product-call-contracts.js';
import {
	bridgeProductReviewAnnotationPublicationIdentitySchema,
	bridgeProductWorktreeAnnotationOperationSchema,
} from './bridge-product-call-contracts.js';
import { bridgeProductReviewPublicationIdSchema } from './bridge-product-review-primitives.js';

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

const bridgeProductControlFileWorktreeAnnotationCommandSchema = z
	.object({
		method: z.literal('file.annotations.command'),
		params: z.object({ operation: bridgeProductWorktreeAnnotationOperationSchema }).strict(),
	})
	.strict();

const bridgeProductControlReviewWorktreeAnnotationCommandSchema = z
	.object({
		method: z.literal('review.annotations.command'),
		params: z
			.object({
				operation: bridgeProductWorktreeAnnotationOperationSchema,
				reviewPublicationIdentity: bridgeProductReviewAnnotationPublicationIdentitySchema,
			})
			.strict(),
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

const bridgeProductControlReviewPublicationInstallAdmitCommandSchema = z
	.object({
		method: z.literal('review.publication.install.admit'),
		params: z
			.object({
				candidatePublicationId: bridgeProductReviewPublicationIdSchema,
				expectedDisplayedPublicationId: bridgeProductReviewPublicationIdSchema.nullable(),
			})
			.strict(),
	})
	.strict();

const bridgeProductControlReviewPublicationAppliedCommandSchema = z
	.object({
		method: z.literal('review.publication.applied'),
		params: z.object({ publicationId: bridgeProductReviewPublicationIdSchema }).strict(),
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
	bridgeProductControlFileWorktreeAnnotationCommandSchema,
	bridgeProductControlReviewWorktreeAnnotationCommandSchema,
	bridgeProductControlMarkFileViewedCommandSchema,
	bridgeProductControlReviewComparisonUpdateCommandSchema,
	bridgeProductControlReviewComparisonTargetsQueryCommandSchema,
	bridgeProductControlReviewPublicationInstallAdmitCommandSchema,
	bridgeProductControlReviewPublicationAppliedCommandSchema,
	bridgeProductControlActiveViewerModeUpdateCommandSchema,
	bridgeProductControlIntakeReadyCommandSchema,
]);

export type BridgeActiveViewerSource = z.infer<typeof bridgeActiveViewerSourceSchema>;
export type BridgeActiveViewerModeUpdate = z.infer<typeof bridgeActiveViewerModeUpdateSchema>;
export type BridgeProductControlCommand = z.infer<typeof bridgeProductControlCommandSchema>;
