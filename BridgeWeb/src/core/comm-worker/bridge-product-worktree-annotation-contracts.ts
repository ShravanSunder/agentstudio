import { z } from 'zod';

import {
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductUnicodeScalarUtf8ByteLength,
} from './bridge-product-contract-primitives.js';
import { bridgeProductReviewPublicationIdSchema } from './bridge-product-review-primitives.js';

const annotationDateSchema = z.number().finite();

const annotationOutputResultSummarySchema = z
	.object({
		attemptId: bridgeProductReviewPublicationIdSchema,
		destinationFilename: z.string().min(1).max(4096).nullable(),
		messageCount: bridgeProductNonnegativeSequenceSchema.positive(),
		outputKind: z.enum(['clipboard_markdown', 'json_file']),
		sessionId: bridgeProductReviewPublicationIdSchema,
	})
	.strict();

const annotationOutputCommandOutcomeSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('destination_cancelled') }).strict(),
	z
		.object({
			kind: z.literal('destination_selection_failed'),
			selectionError: z.string().min(1),
		})
		.strict(),
	z
		.object({
			kind: z.literal('succeeded'),
			summary: annotationOutputResultSummarySchema,
		})
		.strict(),
	z
		.object({
			effectError: z.string().min(1),
			kind: z.literal('effect_failed'),
			summary: annotationOutputResultSummarySchema,
		})
		.strict(),
	z
		.object({
			cleanupError: z.string().min(1),
			effectError: z.string().min(1),
			kind: z.literal('effect_and_cleanup_failed'),
			summary: annotationOutputResultSummarySchema,
		})
		.strict(),
	z
		.object({
			finalizationError: z.string().min(1),
			kind: z.literal('partial_success'),
			summary: annotationOutputResultSummarySchema,
		})
		.strict(),
]);

export const bridgeProductWorktreeAnnotationOutputHistorySummarySchema = z
	.object({
		attemptId: bridgeProductReviewPublicationIdSchema,
		createdAt: annotationDateSchema,
		messageCount: bridgeProductNonnegativeSequenceSchema.positive(),
		outputKind: z.enum(['clipboard_markdown', 'json_file']),
		repeatedFromAttemptId: bridgeProductReviewPublicationIdSchema.nullable(),
		sessionId: bridgeProductReviewPublicationIdSchema,
		state: z.enum(['prepared', 'succeeded', 'unknown', 'finalization_failed']),
		updatedAt: annotationDateSchema,
	})
	.strict();

const annotationCommandOutcomeStatusSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('committed') }).strict(),
	z
		.object({
			candidateSessionIds: z
				.array(bridgeProductReviewPublicationIdSchema)
				.min(1)
				.max(128)
				.refine((sessionIds) => new Set(sessionIds).size === sessionIds.length, {
					message: 'Annotation admission candidates must be unique.',
				}),
			kind: z.literal('admission_required'),
			reason: z.enum(['applicable_session_choice', 'uncertain_continuity_choice']),
		})
		.strict(),
	z
		.object({
			kind: z.literal('output'),
			outcome: annotationOutputCommandOutcomeSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('history'),
			summaries: z
				.array(bridgeProductWorktreeAnnotationOutputHistorySummarySchema)
				.max(128)
				.readonly(),
		})
		.strict(),
	z
		.object({
			code: z.enum([
				'conflict',
				'edit_token_conflict',
				'invalid_source',
				'message_locked',
				'not_found',
				'open_thread_count_conflict',
				'output_unavailable',
				'recovery_acknowledgement_required',
				'session_read_only',
				'session_selection_required',
				'unavailable',
				'unexpected',
				'unresolved_work_confirmation_required',
			]),
			kind: z.literal('failed'),
		})
		.strict(),
]);

const annotationCommandReceiptSchema = z.discriminatedUnion('kind', [
	z
		.object({
			draftRevision: bridgeProductNonnegativeSequenceSchema.nullable(),
			kind: z.literal('message'),
			messageId: bridgeProductReviewPublicationIdSchema,
			messageRevision: bridgeProductNonnegativeSequenceSchema,
			savedRevision: bridgeProductNonnegativeSequenceSchema.positive().nullable(),
			sessionRevision: bridgeProductNonnegativeSequenceSchema,
			threadId: bridgeProductReviewPublicationIdSchema,
		})
		.strict(),
]);

export const bridgeProductWorktreeAnnotationCommandOutcomeSchema = z
	.object({
		receipt: annotationCommandReceiptSchema.optional(),
		requestId: bridgeProductIdentifierSchema,
		sessionId: bridgeProductReviewPublicationIdSchema.nullable(),
		status: annotationCommandOutcomeStatusSchema,
		surface: z.enum(['file', 'review']),
	})
	.strict();

const annotationMessageBodySchema = z.string().refine((body) => {
	const byteLength = bridgeProductUnicodeScalarUtf8ByteLength(body);
	return byteLength !== null && byteLength <= 16 * 1024;
}, 'Annotation message bodies cannot exceed 16 KiB of UTF-8.');

const annotationMessageDraftSchema = z
	.object({
		activeEditToken: bridgeProductIdentifierSchema.nullable(),
		body: annotationMessageBodySchema,
		revision: bridgeProductNonnegativeSequenceSchema,
	})
	.strict();

export const bridgeProductWorktreeAnnotationMessageEntrySchema = z
	.object({
		authorKind: z.literal('human'),
		createdAt: annotationDateSchema,
		draft: annotationMessageDraftSchema.nullable(),
		messageId: bridgeProductReviewPublicationIdSchema,
		messageRevision: bridgeProductNonnegativeSequenceSchema,
		ordinal: bridgeProductNonnegativeSequenceSchema,
		savedBody: annotationMessageBodySchema.nullable(),
		savedRevision: bridgeProductNonnegativeSequenceSchema.positive().nullable(),
		sessionId: bridgeProductReviewPublicationIdSchema,
		sessionRevision: bridgeProductNonnegativeSequenceSchema,
		status: z.enum(['editable', 'locked']),
		threadId: bridgeProductReviewPublicationIdSchema,
	})
	.strict()
	.superRefine((message, context) => {
		if ((message.savedBody === null) !== (message.savedRevision === null)) {
			context.addIssue({
				code: 'custom',
				message: 'Saved body and saved revision must be present or absent together.',
				path: ['savedRevision'],
			});
		}
		if (message.savedBody === null && message.draft === null) {
			context.addIssue({
				code: 'custom',
				message: 'A durable message must contain a saved body or draft.',
				path: ['draft'],
			});
		}
		if (message.savedBody === null && message.draft?.body.trim().length === 0) {
			context.addIssue({
				code: 'custom',
				message: 'A never-saved draft cannot be empty.',
				path: ['draft', 'body'],
			});
		}
		if (message.status === 'locked' && message.draft !== null) {
			context.addIssue({
				code: 'custom',
				message: 'A locked message cannot retain a working draft.',
				path: ['draft'],
			});
		}
	});

export const bridgeProductWorktreeAnnotationEventSchema = z
	.object({
		eventKind: z.literal('snapshot.required'),
		sourceGeneration: bridgeProductNonnegativeSequenceSchema,
		worktreeId: bridgeProductIdentifierSchema,
	})
	.strict();

export type BridgeProductWorktreeAnnotationEvent = z.infer<
	typeof bridgeProductWorktreeAnnotationEventSchema
>;
