import { z } from 'zod';

import { createBridgeMetadataCatalogTransferSchema } from './bridge-metadata-catalog-transfer-contracts.js';
import {
	bridgeProductIdentifierSchema,
	bridgeProductNonnegativeSequenceSchema,
	bridgeProductUnicodeScalarUtf8ByteLength,
} from './bridge-product-contract-primitives.js';
import { bridgeProductReviewPublicationIdSchema } from './bridge-product-review-primitives.js';

const annotationUnixMillisecondsSchema = bridgeProductNonnegativeSequenceSchema;

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
		canMarkNotHandled: z.boolean(),
		createdAtUnixMilliseconds: annotationUnixMillisecondsSchema,
		messageCount: bridgeProductNonnegativeSequenceSchema.positive(),
		outputKind: z.enum(['clipboard_markdown', 'json_file']),
		repeatedFromAttemptId: bridgeProductReviewPublicationIdSchema.nullable(),
		sessionId: bridgeProductReviewPublicationIdSchema,
		state: z.enum(['prepared', 'succeeded', 'unknown', 'finalization_failed']),
		updatedAtUnixMilliseconds: annotationUnixMillisecondsSchema,
	})
	.strict()
	.superRefine((summary, context) => {
		if (summary.state !== 'succeeded' && summary.canMarkNotHandled) {
			context.addIssue({
				code: 'custom',
				message: 'Only successful output history can be marked not handled.',
				path: ['canMarkNotHandled'],
			});
		}
	})
	.transform(({ createdAtUnixMilliseconds, updatedAtUnixMilliseconds, ...summary }) => ({
		...summary,
		createdAt: createdAtUnixMilliseconds,
		updatedAt: updatedAtUnixMilliseconds,
	}));

export const bridgeProductWorktreeAnnotationDecodedOutputHistorySummarySchema = z
	.object({
		attemptId: bridgeProductReviewPublicationIdSchema,
		canMarkNotHandled: z.boolean(),
		createdAt: annotationUnixMillisecondsSchema,
		messageCount: bridgeProductNonnegativeSequenceSchema.positive(),
		outputKind: z.enum(['clipboard_markdown', 'json_file']),
		repeatedFromAttemptId: bridgeProductReviewPublicationIdSchema.nullable(),
		sessionId: bridgeProductReviewPublicationIdSchema,
		state: z.enum(['prepared', 'succeeded', 'unknown', 'finalization_failed']),
		updatedAt: annotationUnixMillisecondsSchema,
	})
	.strict()
	.superRefine((summary, context) => {
		if (summary.state !== 'succeeded' && summary.canMarkNotHandled) {
			context.addIssue({
				code: 'custom',
				message: 'Only successful output history can be marked not handled.',
				path: ['canMarkNotHandled'],
			});
		}
	});

const annotationCommittedCommandOutcomeStatusSchema = z
	.object({ kind: z.literal('committed') })
	.strict();
const annotationAdmissionRequiredCommandOutcomeStatusSchema = z
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
	.strict();
const annotationOutputCommandOutcomeStatusSchema = z
	.object({
		kind: z.literal('output'),
		outcome: annotationOutputCommandOutcomeSchema,
	})
	.strict();
const annotationViewedResultSchema = z.discriminatedUnion('kind', [
	z
		.object({
			committedSessionRevision: bridgeProductNonnegativeSequenceSchema,
			disposition: z.enum(['changed', 'already_viewed']),
			kind: z.literal('viewed'),
			messageId: bridgeProductReviewPublicationIdSchema,
			savedRevision: bridgeProductNonnegativeSequenceSchema.positive(),
		})
		.strict(),
	z
		.object({
			disposition: z.enum(['stale', 'not_agent', 'not_found']),
			expectedSavedRevision: bridgeProductNonnegativeSequenceSchema.positive(),
			kind: z.literal('not_viewed'),
			messageId: bridgeProductReviewPublicationIdSchema,
		})
		.strict(),
]);
const annotationViewedCommandOutcomeStatusSchema = z
	.object({
		kind: z.literal('viewed'),
		results: z.array(annotationViewedResultSchema).min(1).max(256).readonly(),
	})
	.strict()
	.superRefine((status, context) => {
		const identities = status.results.map((result) =>
			result.kind === 'viewed'
				? `${result.messageId}:${result.savedRevision}`
				: `${result.messageId}:${result.expectedSavedRevision}`,
		);
		if (new Set(identities).size !== identities.length) {
			context.addIssue({
				code: 'custom',
				message: 'Viewed annotation results must have unique revision identities.',
				path: ['results'],
			});
		}
	});
const annotationFailedCommandOutcomeStatusSchema = z
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
	.strict();

const annotationCommandOutcomeStatusSchema = z.discriminatedUnion('kind', [
	annotationCommittedCommandOutcomeStatusSchema,
	annotationAdmissionRequiredCommandOutcomeStatusSchema,
	annotationOutputCommandOutcomeStatusSchema,
	z
		.object({
			kind: z.literal('history'),
			summaries: z
				.array(bridgeProductWorktreeAnnotationOutputHistorySummarySchema)
				.max(128)
				.readonly(),
		})
		.strict(),
	annotationFailedCommandOutcomeStatusSchema,
]);

const annotationDecodedCommandOutcomeStatusSchema = z.discriminatedUnion('kind', [
	annotationCommittedCommandOutcomeStatusSchema,
	annotationAdmissionRequiredCommandOutcomeStatusSchema,
	annotationOutputCommandOutcomeStatusSchema,
	z
		.object({
			kind: z.literal('history'),
			summaries: z
				.array(bridgeProductWorktreeAnnotationDecodedOutputHistorySummarySchema)
				.max(128)
				.readonly(),
		})
		.strict(),
	annotationFailedCommandOutcomeStatusSchema,
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
			threadRevision: bridgeProductNonnegativeSequenceSchema,
		})
		.strict(),
]);

const annotationCommandOutcomeCommonShape = {
	requestId: bridgeProductIdentifierSchema,
	sessionId: bridgeProductReviewPublicationIdSchema.nullable(),
	surface: z.enum(['file', 'review']),
} as const;

export const bridgeProductWorktreeAnnotationCommandOutcomeSchema = z.union([
	z
		.object({
			...annotationCommandOutcomeCommonShape,
			receipt: annotationCommandReceiptSchema.optional(),
			status: annotationCommandOutcomeStatusSchema,
		})
		.strict(),
	z
		.object({
			...annotationCommandOutcomeCommonShape,
			receipt: z.null(),
			status: annotationViewedCommandOutcomeStatusSchema,
		})
		.strict()
		.transform(({ receipt: _receipt, ...outcome }) => ({ ...outcome, receipt: undefined })),
]);

export const bridgeProductWorktreeAnnotationDecodedCommandOutcomeSchema = z.union([
	z
		.object({
			...annotationCommandOutcomeCommonShape,
			receipt: annotationCommandReceiptSchema.optional(),
			status: annotationDecodedCommandOutcomeStatusSchema,
		})
		.strict(),
	z
		.object({
			...annotationCommandOutcomeCommonShape,
			receipt: z.undefined().optional(),
			status: annotationViewedCommandOutcomeStatusSchema,
		})
		.strict()
		.transform((outcome) => ({ ...outcome, receipt: undefined })),
]);

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

const annotationMessageEntryShape = {
	attentionState: z.enum(['not_applicable', 'new', 'viewed']),
	authorKind: z.enum(['human', 'agent']),
	draft: annotationMessageDraftSchema.nullable(),
	handled: z.boolean(),
	messageId: bridgeProductReviewPublicationIdSchema,
	messageRevision: bridgeProductNonnegativeSequenceSchema,
	ordinal: bridgeProductNonnegativeSequenceSchema,
	savedBody: annotationMessageBodySchema.nullable(),
	savedRevision: bridgeProductNonnegativeSequenceSchema.positive().nullable(),
	sessionId: bridgeProductReviewPublicationIdSchema,
	sessionRevision: bridgeProductNonnegativeSequenceSchema,
	status: z.enum(['editable', 'locked']),
	threadId: bridgeProductReviewPublicationIdSchema,
	threadRevision: bridgeProductNonnegativeSequenceSchema,
} as const;

export const bridgeProductWorktreeAnnotationDecodedMessageEntrySchema = z
	.object({ ...annotationMessageEntryShape, createdAt: annotationUnixMillisecondsSchema })
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
		if (message.authorKind === 'human' && message.attentionState !== 'not_applicable') {
			context.addIssue({
				code: 'custom',
				message: 'Human annotation messages cannot carry agent attention state.',
				path: ['attentionState'],
			});
		}
		if (message.authorKind === 'agent') {
			if (message.attentionState === 'not_applicable') {
				context.addIssue({
					code: 'custom',
					message: 'Agent annotation messages require New or viewed attention state.',
					path: ['attentionState'],
				});
			}
			if (message.draft !== null) {
				context.addIssue({
					code: 'custom',
					message: 'Agent annotation messages cannot retain a working draft.',
					path: ['draft'],
				});
			}
			if (message.handled) {
				context.addIssue({
					code: 'custom',
					message: 'Agent annotation messages cannot be handled.',
					path: ['handled'],
				});
			}
			if (message.savedBody === null || message.savedRevision === null) {
				context.addIssue({
					code: 'custom',
					message: 'Agent annotation messages require a current saved revision.',
					path: ['savedRevision'],
				});
			}
		}
	});

export const bridgeProductWorktreeAnnotationMessageEntrySchema = z
	.object({
		...annotationMessageEntryShape,
		createdAtUnixMilliseconds: annotationUnixMillisecondsSchema,
	})
	.strict()
	.transform(({ createdAtUnixMilliseconds, ...message }) => ({
		...message,
		createdAt: createdAtUnixMilliseconds,
	}))
	.pipe(bridgeProductWorktreeAnnotationDecodedMessageEntrySchema);

export const bridgeProductWorktreeAnnotationCatalogEntrySchema = z.discriminatedUnion('kind', [
	z
		.object({
			kind: z.literal('session'),
			semanticRevision: bridgeProductNonnegativeSequenceSchema,
			sessionId: bridgeProductReviewPublicationIdSchema,
		})
		.strict(),
	z
		.object({
			createdOrdinal: bridgeProductNonnegativeSequenceSchema,
			kind: z.literal('thread'),
			scope: z.enum(['located', 'whole_file', 'session']),
			sessionId: bridgeProductReviewPublicationIdSchema,
			threadId: bridgeProductReviewPublicationIdSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('message'),
			messageId: bridgeProductReviewPublicationIdSchema,
			ordinal: bridgeProductNonnegativeSequenceSchema,
			threadId: bridgeProductReviewPublicationIdSchema,
		})
		.strict(),
]);

export const bridgeProductWorktreeAnnotationEventAuthoritySchema = z
	.object({
		applicationSourceGeneration: bridgeProductNonnegativeSequenceSchema,
		worktreeId: bridgeProductIdentifierSchema,
	})
	.strict();

const bridgeProductWorktreeAnnotationCatalogTransferSchema =
	createBridgeMetadataCatalogTransferSchema(bridgeProductWorktreeAnnotationCatalogEntrySchema);

const bridgeProductWorktreeAnnotationCatalogEventSchema = z
	.object({
		authority: bridgeProductWorktreeAnnotationEventAuthoritySchema,
		kind: z.literal('annotation.catalog'),
		transfer: bridgeProductWorktreeAnnotationCatalogTransferSchema,
	})
	.strict()
	.superRefine((event, context) => {
		if (event.transfer.catalogRevision === event.authority.applicationSourceGeneration) return;
		context.addIssue({
			code: 'custom',
			message: 'Annotation catalog revision must equal its application source generation.',
			path: ['transfer', 'catalogRevision'],
		});
	});

const bridgeProductWorktreeAnnotationSessionChangedEventSchema = z
	.object({
		authority: bridgeProductWorktreeAnnotationEventAuthoritySchema,
		kind: z.literal('annotation.sessionChanged'),
		semanticRevision: bridgeProductNonnegativeSequenceSchema.positive(),
		sessionId: bridgeProductReviewPublicationIdSchema,
	})
	.strict();

const bridgeProductWorktreeAnnotationControlChangedEventSchema = z
	.object({
		authority: bridgeProductWorktreeAnnotationEventAuthoritySchema,
		kind: z.literal('annotation.controlChanged'),
		reason: z.enum(['discovery', 'recovery']),
	})
	.strict();

export const bridgeProductWorktreeAnnotationEventSchema = z.union([
	bridgeProductWorktreeAnnotationCatalogEventSchema,
	bridgeProductWorktreeAnnotationSessionChangedEventSchema,
	bridgeProductWorktreeAnnotationControlChangedEventSchema,
]);

export type BridgeProductWorktreeAnnotationEvent = z.infer<
	typeof bridgeProductWorktreeAnnotationEventSchema
>;
export type BridgeProductWorktreeAnnotationCatalogEntry = z.infer<
	typeof bridgeProductWorktreeAnnotationCatalogEntrySchema
>;
export type BridgeProductWorktreeAnnotationEventAuthority = z.infer<
	typeof bridgeProductWorktreeAnnotationEventAuthoritySchema
>;
