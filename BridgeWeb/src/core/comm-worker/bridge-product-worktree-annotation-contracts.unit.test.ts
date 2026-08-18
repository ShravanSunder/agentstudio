import { describe, expect, test } from 'vitest';

import {
	bridgeProductWorktreeAnnotationEventSchema,
	bridgeProductWorktreeAnnotationMessageEntrySchema,
} from './bridge-product-worktree-annotation-contracts.js';

const lowercaseSessionId = '01890abc-def0-7abc-8def-0123456789ab';

describe('Bridge product worktree annotation contracts', () => {
	test('requires a nonnegative fixed-size expected thread count', () => {
		const projection = annotationProjectionWithSession(lowercaseSessionId);
		const payload = projection['payload'] as Readonly<Record<string, unknown>>;
		const { expectedThreadCount: _omitted, ...missingExpectedThreadCount } = payload;

		expect(
			bridgeProductWorktreeAnnotationEventSchema.safeParse({
				...projection,
				payload: missingExpectedThreadCount,
			}).success,
		).toBe(false);
		for (const expectedThreadCount of [-1, 'unknown']) {
			expect(
				bridgeProductWorktreeAnnotationEventSchema.safeParse({
					...projection,
					payload: { ...payload, expectedThreadCount },
				}).success,
			).toBe(false);
		}
	});

	test('admits only lowercase UUIDv7 annotation identities in projections', () => {
		const lowercaseProjection = annotationProjectionWithSession(lowercaseSessionId);

		expect(bridgeProductWorktreeAnnotationEventSchema.parse(lowercaseProjection)).toEqual(
			lowercaseProjection,
		);
		expect(
			bridgeProductWorktreeAnnotationEventSchema.safeParse(
				annotationProjectionWithSession(lowercaseSessionId.toUpperCase()),
			).success,
		).toBe(false);
		expect(
			bridgeProductWorktreeAnnotationEventSchema.safeParse(
				annotationProjectionWithSession('01890abc-def0-4abc-8def-0123456789ab'),
			).success,
		).toBe(false);
	});

	test('models saved content, optional draft, and durable status directly', () => {
		const messageId = '01890abc-def0-7abc-8def-012345678901';
		const threadId = '01890abc-def0-7abc-8def-012345678902';
		const baseMessage = {
			authorKind: 'human',
			createdAt: 1,
			messageId,
			messageRevision: 2,
			ordinal: 0,
			sessionId: lowercaseSessionId,
			sessionRevision: 3,
			status: 'editable',
			threadId,
		} as const;
		const neverSavedDraft = {
			...baseMessage,
			draft: { activeEditToken: 'edit-token-1', body: 'Draft body', revision: 1 },
			savedBody: null,
			savedRevision: null,
		} as const;
		const savedMessage = {
			...baseMessage,
			draft: null,
			savedBody: 'Saved body',
			savedRevision: 1,
		} as const;
		const savedMessageWithEmptyDraft = {
			...savedMessage,
			draft: { activeEditToken: null, body: '', revision: 2 },
		} as const;

		for (const message of [neverSavedDraft, savedMessage, savedMessageWithEmptyDraft]) {
			expect(bridgeProductWorktreeAnnotationMessageEntrySchema.parse(message)).toEqual(message);
		}
		for (const rejected of [
			{ ...baseMessage, draft: null, savedBody: null, savedRevision: null },
			{ ...savedMessage, savedRevision: null },
			{ ...neverSavedDraft, savedRevision: 1 },
			{ ...neverSavedDraft, draft: { ...neverSavedDraft.draft, body: '   ' } },
			{ ...savedMessage, status: 'provisional' },
			{ ...savedMessage, readiness: 'saved' },
			{ ...savedMessage, createdAt: undefined },
			{ ...savedMessage, savedRevision: undefined },
		] as const) {
			expect(bridgeProductWorktreeAnnotationMessageEntrySchema.safeParse(rejected).success).toBe(
				false,
			);
		}
	});

	test('admits only complete located thread contexts', () => {
		const locatedContext = {
			diffSide: null,
			endLine: 12,
			path: 'Sources/App/View.swift',
			placement: 'exact',
			resolution: 'open',
			scope: 'located',
			sourceIdentity: 'descriptor-file-1',
			sourceRole: 'file',
			startLine: 10,
			threadId: '01890abc-def0-7abc-8def-012345678902',
		} as const;

		expect(
			bridgeProductWorktreeAnnotationEventSchema.parse(annotationMessageBatch(locatedContext)),
		).toEqual(annotationMessageBatch(locatedContext));
		for (const rejectedContext of [
			{ ...locatedContext, scope: 'whole_file' },
			{ ...locatedContext, scope: 'session' },
			{ ...locatedContext, path: null },
			{ ...locatedContext, sourceIdentity: null },
			{ ...locatedContext, sourceRole: null },
			{ ...locatedContext, startLine: null },
			{ ...locatedContext, endLine: null },
			{ ...locatedContext, endLine: 9 },
		] as const) {
			expect(
				bridgeProductWorktreeAnnotationEventSchema.safeParse(
					annotationMessageBatch(rejectedContext),
				).success,
			).toBe(false);
		}
	});

	test('projects strict bounded admission-required outcomes for the blocked inline intent', () => {
		const admissionOutcome = {
			requestId: 'annotation-request-1',
			sessionId: null,
			status: {
				candidateSessionIds: [lowercaseSessionId],
				kind: 'admission_required',
				reason: 'uncertain_continuity_choice',
			},
			surface: 'file',
		} as const;
		const admissionRequiredProjection = annotationProjectionWithSession(lowercaseSessionId, [
			admissionOutcome,
		]);

		expect(bridgeProductWorktreeAnnotationEventSchema.parse(admissionRequiredProjection)).toEqual(
			admissionRequiredProjection,
		);
		expect(
			bridgeProductWorktreeAnnotationEventSchema.safeParse(
				annotationProjectionWithSession(lowercaseSessionId, [
					{
						...admissionOutcome,
						status: {
							...admissionOutcome.status,
							candidateSessionIds: [lowercaseSessionId, lowercaseSessionId],
						},
					},
				]),
			).success,
		).toBe(false);
	});
});

function annotationMessageBatch(
	context: Readonly<Record<string, unknown>>,
): Readonly<Record<string, unknown>> {
	return {
		eventKind: 'message.batch',
		payload: {
			context,
			isLastBatchForThread: true,
			messages: [
				{
					authorKind: 'human',
					createdAt: 1,
					draft: null,
					messageId: '01890abc-def0-7abc-8def-012345678901',
					messageRevision: 1,
					ordinal: 0,
					savedBody: 'Saved body',
					savedRevision: 1,
					sessionId: lowercaseSessionId,
					sessionRevision: 1,
					status: 'editable',
					threadId: '01890abc-def0-7abc-8def-012345678902',
				},
			],
			revision: 1,
		},
	};
}

function annotationProjectionWithSession(
	sessionId: string,
	commandOutcomes: readonly Readonly<Record<string, unknown>>[] = [],
): Readonly<Record<string, unknown>> {
	return {
		eventKind: 'projection.state',
		payload: {
			commandOutcomes,
			expectedThreadCount: 0,
			outputHistory: [],
			recoveryStatus: 'available',
			revision: 1,
			sessions: [
				{
					completedAt: null,
					createdAt: 1,
					eligibleMessageCount: 0,
					eligibleWithoutInlinePlacementCount: 0,
					lifecycle: 'living',
					semanticRevision: 1,
					sessionId,
					sourceRelationship: 'applicable',
					updatedAt: 1,
				},
			],
			worktreeId: 'worktree-1',
		},
	};
}
