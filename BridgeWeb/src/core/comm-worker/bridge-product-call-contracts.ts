import { z } from 'zod';

import { bridgeProductReviewComparisonTargetsContentDescriptorSchema } from './bridge-product-content-contracts.js';
import {
	type BridgeProductAssert,
	bridgeProductDisplayPathSchema,
	bridgeProductIdentifierSchema,
	bridgeProductUnicodeScalarUtf8ByteLength,
	type BridgeProductRegistryValue,
	type BridgeProductTypeSetsEqual,
} from './bridge-product-contract-primitives.js';
import { bridgeProductReviewComparisonTargetSchema } from './bridge-product-review-comparison-contracts.js';
import { bridgeProductReviewPublicationIdSchema } from './bridge-product-review-primitives.js';
import { bridgeProductFileSourceConfigurationSchema } from './bridge-product-subscription-contracts.js';
import { bridgeProductWorktreeAnnotationCommandOutcomeSchema } from './bridge-product-worktree-annotation-contracts.js';
import {
	bridgeProductWorktreeAnnotationOutputCandidatePageSchema,
	bridgeProductWorktreeAnnotationOutputCandidateQueryRequestSchema,
	bridgeProductWorktreeAnnotationOutputInspectRequestSchema,
	bridgeProductWorktreeAnnotationOutputInspectResultSchema,
} from './bridge-product-worktree-annotation-output-contracts.js';
import {
	bridgeProductAnnotationProjectionQueryRequestSchema,
	bridgeProductAnnotationProjectionQueryResultSchema,
} from './bridge-product-worktree-annotation-projection-query-contracts.js';

export { bridgeProductWorktreeAnnotationOutputInspectResultSchema } from './bridge-product-worktree-annotation-output-contracts.js';

export { bridgeProductReviewComparisonTargetSchema } from './bridge-product-review-comparison-contracts.js';

export const bridgeProductFileSourceCurrentRequestSchema = z.object({}).strict();
export const bridgeProductFileRefreshRetryRequestSchema = z.object({}).strict();
export const bridgeProductFileRefreshRetryResultSchema = z.null();
export const bridgeProductFileSourceCurrentResultSchema = z.discriminatedUnion('status', [
	z
		.object({
			source: bridgeProductFileSourceConfigurationSchema,
			status: z.literal('available'),
		})
		.strict(),
	z
		.object({
			reason: z.literal('no-file-source-authority'),
			status: z.literal('unavailable'),
		})
		.strict(),
]);

export const bridgeProductReviewMarkFileViewedRequestSchema = z
	.object({ itemId: bridgeProductIdentifierSchema })
	.strict();
export const bridgeProductReviewMarkFileViewedResultSchema = z.null();
export const bridgeProductReviewIntakeReadyRequestSchema = z
	.object({
		reason: bridgeProductIdentifierSchema.nullable(),
		streamId: bridgeProductIdentifierSchema.nullable(),
	})
	.strict();
export const bridgeProductReviewIntakeReadyResultSchema = z.null();
export const bridgeProductReviewPublicationAppliedRequestSchema = z
	.object({ publicationId: bridgeProductReviewPublicationIdSchema })
	.strict();
export const bridgeProductReviewPublicationAppliedResultSchema = z.null();

export const bridgeProductReviewComparisonUpdateRequestSchema = z
	.object({ target: bridgeProductReviewComparisonTargetSchema })
	.strict();
export const bridgeProductReviewComparisonUpdateResultSchema = z.null();
export const bridgeProductReviewComparisonTargetsQueryRequestSchema = z.object({}).strict();
export const bridgeProductReviewComparisonTargetsQueryResultSchema = z
	.object({
		descriptor: bridgeProductReviewComparisonTargetsContentDescriptorSchema,
	})
	.strict();

const bridgeProductActiveViewerSourceBaseSchema = z
	.object({
		generation: z.number().int().nonnegative(),
		streamId: bridgeProductIdentifierSchema,
	})
	.strict();

export const bridgeProductReviewActiveViewerModeUpdateRequestSchema = z
	.object({
		activeSource: bridgeProductActiveViewerSourceBaseSchema.nullable(),
		nativeSelectionRequestId: bridgeProductIdentifierSchema.nullable(),
		sequence: z.number().int().positive(),
		sessionId: bridgeProductIdentifierSchema,
	})
	.strict();
export const bridgeProductFileActiveViewerModeUpdateRequestSchema = z
	.object({
		activeSource: bridgeProductActiveViewerSourceBaseSchema.nullable(),
		nativeSelectionRequestId: bridgeProductIdentifierSchema.nullable(),
		sequence: z.number().int().positive(),
		sessionId: bridgeProductIdentifierSchema,
	})
	.strict();
export const bridgeProductActiveViewerModeUpdateResultSchema = z.null();

const bridgeProductWorktreeAnnotationIdSchema = bridgeProductReviewPublicationIdSchema;
const bridgeProductWorktreeAnnotationBodySchema = z
	.string()
	.refine((body) => body.trim().length > 0, 'Annotation bodies cannot be empty.')
	.refine((body) => {
		const byteLength = bridgeProductUnicodeScalarUtf8ByteLength(body);
		return byteLength !== null && byteLength <= 16 * 1024;
	}, 'Annotation bodies cannot exceed 16 KiB of UTF-8.');
const bridgeProductWorktreeAnnotationDraftEditBodySchema = z.string().refine((body) => {
	const byteLength = bridgeProductUnicodeScalarUtf8ByteLength(body);
	return byteLength !== null && byteLength <= 16 * 1024;
}, 'Annotation draft edits cannot exceed 16 KiB of UTF-8.');
const bridgeProductWorktreeAnnotationAdmissionSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('implicitOrSingle') }).strict(),
	z.object({ kind: z.literal('newSession') }).strict(),
	z
		.object({
			kind: z.literal('selected'),
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
		})
		.strict(),
]);
const bridgeProductWorktreeAnnotationOriginSchema = z
	.object({
		diffSide: z.enum(['additions', 'deletions']).nullable(),
		endLine: z.number().int().positive(),
		kind: z.literal('located'),
		path: bridgeProductDisplayPathSchema,
		sourceIdentity: bridgeProductIdentifierSchema,
		sourceRole: z.enum(['file', 'reviewBase', 'reviewHead']),
		startLine: z.number().int().positive(),
	})
	.strict()
	.refine((origin) => origin.endLine >= origin.startLine, {
		message: 'Annotation endLine cannot precede startLine.',
	});
const bridgeProductWorktreeAnnotationMessageIdChunkSchema = z
	.array(bridgeProductWorktreeAnnotationIdSchema)
	.min(1)
	.max(64)
	.refine((messageIds) => new Set(messageIds).size === messageIds.length, {
		message: 'Annotation output selection cannot repeat a message identity.',
	});
const bridgeProductWorktreeAnnotationOutputSelectionModeSchema = z.enum([
	'explicit',
	'allEligible',
]);
export const bridgeProductWorktreeAnnotationOperationSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('session.discover') }).strict(),
	z
		.object({
			kind: z.literal('demand.acquire'),
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('demand.release'),
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
		})
		.strict(),
	z
		.object({
			admission: bridgeProductWorktreeAnnotationAdmissionSchema,
			body: bridgeProductWorktreeAnnotationBodySchema,
			editToken: bridgeProductIdentifierSchema,
			kind: z.literal('root.create'),
			origin: bridgeProductWorktreeAnnotationOriginSchema,
		})
		.strict(),
	z
		.object({
			body: bridgeProductWorktreeAnnotationBodySchema,
			editToken: bridgeProductIdentifierSchema,
			expectedSessionRevision: z.number().int().nonnegative(),
			kind: z.literal('reply.create'),
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
			threadId: bridgeProductWorktreeAnnotationIdSchema,
		})
		.strict(),
	z
		.object({
			body: bridgeProductWorktreeAnnotationDraftEditBodySchema,
			editToken: bridgeProductIdentifierSchema,
			expectedDraftRevision: z.number().int().nonnegative().nullable(),
			expectedSessionRevision: z.number().int().nonnegative(),
			kind: z.literal('draft.flush'),
			messageId: bridgeProductWorktreeAnnotationIdSchema,
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
		})
		.strict(),
	...(['draft.edit.acquire', 'draft.edit.release'] as const).map((kind) =>
		z
			.object({
				editToken: bridgeProductIdentifierSchema,
				expectedDraftRevision: z.number().int().nonnegative(),
				expectedSessionRevision: z.number().int().nonnegative(),
				kind: z.literal(kind),
				messageId: bridgeProductWorktreeAnnotationIdSchema,
				sessionId: bridgeProductWorktreeAnnotationIdSchema,
			})
			.strict(),
	),
	...(['draft.save', 'draft.revert'] as const).map((kind) =>
		z
			.object({
				editToken: bridgeProductIdentifierSchema,
				expectedDraftRevision: z.number().int().nonnegative(),
				expectedSessionRevision: z.number().int().nonnegative(),
				kind: z.literal(kind),
				messageId: bridgeProductWorktreeAnnotationIdSchema,
				sessionId: bridgeProductWorktreeAnnotationIdSchema,
			})
			.strict(),
	),
	z
		.object({
			expectedSessionRevision: z.number().int().nonnegative(),
			kind: z.literal('thread.resolution.set'),
			resolution: z.enum(['open', 'resolved']),
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
			threadId: bridgeProductWorktreeAnnotationIdSchema,
		})
		.strict(),
	z
		.object({
			decision: z.enum(['acceptCurrentSource', 'keepDetached']),
			expectedSessionRevision: z.number().int().nonnegative(),
			kind: z.literal('continuity.choose'),
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('source.refresh'),
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
			sourceEpoch: z.number().int().nonnegative(),
		})
		.strict(),
	z
		.object({
			kind: z.literal('output.selection.begin'),
			outputKind: z.enum(['clipboardMarkdown', 'jsonFile']),
			selectionMode: bridgeProductWorktreeAnnotationOutputSelectionModeSchema,
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
			transferId: bridgeProductIdentifierSchema,
		})
		.strict(),
	z
		.object({
			kind: z.literal('output.selection.chunk'),
			messageIds: bridgeProductWorktreeAnnotationMessageIdChunkSchema,
			ordinal: z.number().int().nonnegative(),
			selectionMode: bridgeProductWorktreeAnnotationOutputSelectionModeSchema,
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
			transferId: bridgeProductIdentifierSchema,
		})
		.strict(),
	...(['output.selection.commit', 'output.selection.cancel'] as const).map((kind) =>
		z
			.object({
				kind: z.literal(kind),
				selectionMode: bridgeProductWorktreeAnnotationOutputSelectionModeSchema,
				sessionId: bridgeProductWorktreeAnnotationIdSchema,
				transferId: bridgeProductIdentifierSchema,
			})
			.strict(),
	),
	z
		.object({
			kind: z.literal('output.history'),
			sessionId: bridgeProductWorktreeAnnotationIdSchema,
		})
		.strict(),
	z
		.object({
			attemptId: bridgeProductWorktreeAnnotationIdSchema,
			kind: z.literal('output.repeat'),
		})
		.strict(),
	z.object({ kind: z.literal('recovery.acknowledge') }).strict(),
]);
export const bridgeProductWorktreeAnnotationCommandRequestSchema = z
	.object({ operation: bridgeProductWorktreeAnnotationOperationSchema })
	.strict();
export const bridgeProductWorktreeAnnotationCommandResultSchema = z
	.object({
		kind: z.literal('completed'),
		outcome: bridgeProductWorktreeAnnotationCommandOutcomeSchema,
	})
	.strict();

const bridgeProductFileAnnotationOutputInspectResultSchema =
	bridgeProductWorktreeAnnotationOutputInspectResultSchema.refine(
		(result) => result.descriptor.surface === 'file',
		{
			message: 'File annotation output descriptors must remain File-surface bound.',
			path: ['descriptor', 'surface'],
		},
	);
const bridgeProductReviewAnnotationOutputInspectResultSchema =
	bridgeProductWorktreeAnnotationOutputInspectResultSchema.refine(
		(result) => result.descriptor.surface === 'review',
		{
			message: 'Review annotation output descriptors must remain Review-surface bound.',
			path: ['descriptor', 'surface'],
		},
	);

export type BridgeProductWorktreeAnnotationOperation = z.infer<
	typeof bridgeProductWorktreeAnnotationOperationSchema
>;

export type BridgeProductCallRegistry = {
	readonly 'file.annotations.command': {
		readonly request: z.infer<typeof bridgeProductWorktreeAnnotationCommandRequestSchema>;
		readonly result: z.infer<typeof bridgeProductWorktreeAnnotationCommandResultSchema>;
		readonly surface: 'file';
	};
	readonly 'file.annotations.output.inspect': {
		readonly request: z.infer<typeof bridgeProductWorktreeAnnotationOutputInspectRequestSchema>;
		readonly result: z.infer<typeof bridgeProductWorktreeAnnotationOutputInspectResultSchema>;
		readonly surface: 'file';
	};
	readonly 'file.annotations.output.candidates.query': {
		readonly request: z.infer<
			typeof bridgeProductWorktreeAnnotationOutputCandidateQueryRequestSchema
		>;
		readonly result: z.infer<typeof bridgeProductWorktreeAnnotationOutputCandidatePageSchema>;
		readonly surface: 'file';
	};
	readonly 'file.annotations.projection.query': {
		readonly request: z.infer<typeof bridgeProductAnnotationProjectionQueryRequestSchema>;
		readonly result: z.infer<typeof bridgeProductAnnotationProjectionQueryResultSchema>;
		readonly surface: 'file';
	};
	readonly 'file.source.current': {
		readonly request: z.infer<typeof bridgeProductFileSourceCurrentRequestSchema>;
		readonly result: z.infer<typeof bridgeProductFileSourceCurrentResultSchema>;
		readonly surface: 'file';
	};
	readonly 'file.refresh.retry': {
		readonly request: z.infer<typeof bridgeProductFileRefreshRetryRequestSchema>;
		readonly result: z.infer<typeof bridgeProductFileRefreshRetryResultSchema>;
		readonly surface: 'file';
	};
	readonly 'file.activeViewerMode.update': {
		readonly request: z.infer<typeof bridgeProductFileActiveViewerModeUpdateRequestSchema>;
		readonly result: z.infer<typeof bridgeProductActiveViewerModeUpdateResultSchema>;
		readonly surface: 'file';
	};
	readonly 'review.markFileViewed': {
		readonly request: z.infer<typeof bridgeProductReviewMarkFileViewedRequestSchema>;
		readonly result: z.infer<typeof bridgeProductReviewMarkFileViewedResultSchema>;
		readonly surface: 'review';
	};
	readonly 'review.intake.ready': {
		readonly request: z.infer<typeof bridgeProductReviewIntakeReadyRequestSchema>;
		readonly result: z.infer<typeof bridgeProductReviewIntakeReadyResultSchema>;
		readonly surface: 'review';
	};
	readonly 'review.publication.applied': {
		readonly request: z.infer<typeof bridgeProductReviewPublicationAppliedRequestSchema>;
		readonly result: z.infer<typeof bridgeProductReviewPublicationAppliedResultSchema>;
		readonly surface: 'review';
	};
	readonly 'review.activeViewerMode.update': {
		readonly request: z.infer<typeof bridgeProductReviewActiveViewerModeUpdateRequestSchema>;
		readonly result: z.infer<typeof bridgeProductActiveViewerModeUpdateResultSchema>;
		readonly surface: 'review';
	};
	readonly 'review.comparison.update': {
		readonly request: z.infer<typeof bridgeProductReviewComparisonUpdateRequestSchema>;
		readonly result: z.infer<typeof bridgeProductReviewComparisonUpdateResultSchema>;
		readonly surface: 'review';
	};
	readonly 'review.comparisonTargets.query': {
		readonly request: z.infer<typeof bridgeProductReviewComparisonTargetsQueryRequestSchema>;
		readonly result: z.infer<typeof bridgeProductReviewComparisonTargetsQueryResultSchema>;
		readonly surface: 'review';
	};
	readonly 'review.annotations.command': {
		readonly request: z.infer<typeof bridgeProductWorktreeAnnotationCommandRequestSchema>;
		readonly result: z.infer<typeof bridgeProductWorktreeAnnotationCommandResultSchema>;
		readonly surface: 'review';
	};
	readonly 'review.annotations.output.inspect': {
		readonly request: z.infer<typeof bridgeProductWorktreeAnnotationOutputInspectRequestSchema>;
		readonly result: z.infer<typeof bridgeProductWorktreeAnnotationOutputInspectResultSchema>;
		readonly surface: 'review';
	};
	readonly 'review.annotations.output.candidates.query': {
		readonly request: z.infer<
			typeof bridgeProductWorktreeAnnotationOutputCandidateQueryRequestSchema
		>;
		readonly result: z.infer<typeof bridgeProductWorktreeAnnotationOutputCandidatePageSchema>;
		readonly surface: 'review';
	};
	readonly 'review.annotations.projection.query': {
		readonly request: z.infer<typeof bridgeProductAnnotationProjectionQueryRequestSchema>;
		readonly result: z.infer<typeof bridgeProductAnnotationProjectionQueryResultSchema>;
		readonly surface: 'review';
	};
};

export type BridgeProductCallKind = keyof BridgeProductCallRegistry;
export type BridgeProductCallRequest<TCallKind extends BridgeProductCallKind> =
	BridgeProductRegistryValue<BridgeProductCallRegistry, TCallKind, 'request'>;
export type BridgeProductCallResult<TCallKind extends BridgeProductCallKind> =
	BridgeProductRegistryValue<BridgeProductCallRegistry, TCallKind, 'result'>;

const bridgeProductSurfaceByCallKind = {
	'file.annotations.command': 'file',
	'file.annotations.output.inspect': 'file',
	'file.annotations.output.candidates.query': 'file',
	'file.annotations.projection.query': 'file',
	'file.activeViewerMode.update': 'file',
	'file.source.current': 'file',
	'file.refresh.retry': 'file',
	'review.activeViewerMode.update': 'review',
	'review.comparison.update': 'review',
	'review.comparisonTargets.query': 'review',
	'review.intake.ready': 'review',
	'review.markFileViewed': 'review',
	'review.publication.applied': 'review',
	'review.annotations.command': 'review',
	'review.annotations.output.inspect': 'review',
	'review.annotations.output.candidates.query': 'review',
	'review.annotations.projection.query': 'review',
} as const satisfies {
	readonly [TCallKind in BridgeProductCallKind]: BridgeProductCallRegistry[TCallKind]['surface'];
};

export function bridgeProductSurfaceForCallKind<TCallKind extends BridgeProductCallKind>(
	callKind: TCallKind,
): BridgeProductCallRegistry[TCallKind]['surface'] {
	return bridgeProductSurfaceByCallKind[callKind];
}

export const bridgeProductCallRequestSchema = z.discriminatedUnion('method', [
	z
		.object({
			method: z.literal('file.annotations.projection.query'),
			request: bridgeProductAnnotationProjectionQueryRequestSchema.refine(
				(request) => request.surface === 'file',
				{ message: 'File annotation projection query must remain File-surface bound.' },
			),
		})
		.strict(),
	z
		.object({
			method: z.literal('file.annotations.output.candidates.query'),
			request: bridgeProductWorktreeAnnotationOutputCandidateQueryRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.annotations.command'),
			request: bridgeProductWorktreeAnnotationCommandRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.annotations.output.inspect'),
			request: bridgeProductWorktreeAnnotationOutputInspectRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.source.current'),
			request: bridgeProductFileSourceCurrentRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.refresh.retry'),
			request: bridgeProductFileRefreshRetryRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.activeViewerMode.update'),
			request: bridgeProductFileActiveViewerModeUpdateRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.activeViewerMode.update'),
			request: bridgeProductReviewActiveViewerModeUpdateRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.comparison.update'),
			request: bridgeProductReviewComparisonUpdateRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.comparisonTargets.query'),
			request: bridgeProductReviewComparisonTargetsQueryRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.markFileViewed'),
			request: bridgeProductReviewMarkFileViewedRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.intake.ready'),
			request: bridgeProductReviewIntakeReadyRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.publication.applied'),
			request: bridgeProductReviewPublicationAppliedRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.annotations.command'),
			request: bridgeProductWorktreeAnnotationCommandRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.annotations.output.inspect'),
			request: bridgeProductWorktreeAnnotationOutputInspectRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.annotations.output.candidates.query'),
			request: bridgeProductWorktreeAnnotationOutputCandidateQueryRequestSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.annotations.projection.query'),
			request: bridgeProductAnnotationProjectionQueryRequestSchema.refine(
				(request) => request.surface === 'review',
				{ message: 'Review annotation projection query must remain Review-surface bound.' },
			),
		})
		.strict(),
]);

export const bridgeProductCallResultSchema = z.discriminatedUnion('method', [
	z
		.object({
			method: z.literal('file.annotations.projection.query'),
			result: bridgeProductAnnotationProjectionQueryResultSchema.refine(
				(result) => result.descriptor.surface === 'file',
				{ message: 'File annotation projection descriptor must remain File-surface bound.' },
			),
		})
		.strict(),
	z
		.object({
			method: z.literal('file.annotations.output.candidates.query'),
			result: bridgeProductWorktreeAnnotationOutputCandidatePageSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.annotations.command'),
			result: bridgeProductWorktreeAnnotationCommandResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.annotations.output.inspect'),
			result: bridgeProductFileAnnotationOutputInspectResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.source.current'),
			result: bridgeProductFileSourceCurrentResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.refresh.retry'),
			result: bridgeProductFileRefreshRetryResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('file.activeViewerMode.update'),
			result: bridgeProductActiveViewerModeUpdateResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.activeViewerMode.update'),
			result: bridgeProductActiveViewerModeUpdateResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.comparison.update'),
			result: bridgeProductReviewComparisonUpdateResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.comparisonTargets.query'),
			result: bridgeProductReviewComparisonTargetsQueryResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.markFileViewed'),
			result: bridgeProductReviewMarkFileViewedResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.intake.ready'),
			result: bridgeProductReviewIntakeReadyResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.publication.applied'),
			result: bridgeProductReviewPublicationAppliedResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.annotations.command'),
			result: bridgeProductWorktreeAnnotationCommandResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.annotations.output.inspect'),
			result: bridgeProductReviewAnnotationOutputInspectResultSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.annotations.output.candidates.query'),
			result: bridgeProductWorktreeAnnotationOutputCandidatePageSchema,
		})
		.strict(),
	z
		.object({
			method: z.literal('review.annotations.projection.query'),
			result: bridgeProductAnnotationProjectionQueryResultSchema.refine(
				(result) => result.descriptor.surface === 'review',
				{ message: 'Review annotation projection descriptor must remain Review-surface bound.' },
			),
		})
		.strict(),
]);

export type BridgeProductCallRequestWire = z.infer<typeof bridgeProductCallRequestSchema>;
export type BridgeProductCallResultWire = z.infer<typeof bridgeProductCallResultSchema>;
export type BridgeProductCallRequestRegistryParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<BridgeProductCallRequestWire['method'], BridgeProductCallKind>
>;
export type BridgeProductCallResultRegistryParity = BridgeProductAssert<
	BridgeProductTypeSetsEqual<BridgeProductCallResultWire['method'], BridgeProductCallKind>
>;
