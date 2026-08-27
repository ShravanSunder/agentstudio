import { describe, expect, test } from 'vitest';

import {
	bridgeProductWorktreeAnnotationCommandOutcomeSchema,
	bridgeProductWorktreeAnnotationEventSchema,
	bridgeProductWorktreeAnnotationMessageEntrySchema,
	bridgeProductWorktreeAnnotationOutputHistorySummarySchema,
} from './bridge-product-worktree-annotation-contracts.js';

const lowercaseSessionId = '01890abc-def0-7abc-8def-0123456789ab';

describe('Bridge product worktree annotation contracts', () => {
	test('accepts an exact committed message correlation receipt', () => {
		const outcome = {
			receipt: {
				draftRevision: 0,
				kind: 'message',
				messageId: '01890abc-def0-7abc-8def-012345678901',
				messageRevision: 0,
				savedRevision: null,
				sessionRevision: 1,
				threadId: '01890abc-def0-7abc-8def-012345678902',
				threadRevision: 1,
			},
			requestId: 'annotation-command-1',
			sessionId: lowercaseSessionId,
			status: { kind: 'committed' },
			surface: 'file',
		} as const;

		expect(bridgeProductWorktreeAnnotationCommandOutcomeSchema.parse(outcome)).toEqual(outcome);
	});

	test('accepts the strict catalog, session-change, and control-change metadata events', () => {
		const authority = {
			applicationSourceGeneration: 7,
			worktreeId: 'worktree-1',
		} as const;
		const transferId = '01890abc-def0-7abc-8def-012345678900';
		const events = [
			{
				authority,
				kind: 'annotation.catalog',
				transfer: {
					catalogRevision: 7,
					entries: [
						{ kind: 'session', semanticRevision: 3, sessionId: lowercaseSessionId },
						{
							createdOrdinal: 0,
							kind: 'thread',
							scope: 'whole_file',
							sessionId: lowercaseSessionId,
							threadId: '01890abc-def0-7abc-8def-012345678902',
						},
						{
							kind: 'message',
							messageId: '01890abc-def0-7abc-8def-012345678901',
							ordinal: 0,
							threadId: '01890abc-def0-7abc-8def-012345678902',
						},
					],
					kind: 'catalog.window',
					transferId,
					windowOrdinal: 0,
				},
			},
			{
				authority,
				kind: 'annotation.sessionChanged',
				semanticRevision: 4,
				sessionId: lowercaseSessionId,
			},
			{ authority, kind: 'annotation.controlChanged', reason: 'recovery' },
		] as const;

		for (const event of events) {
			expect(bridgeProductWorktreeAnnotationEventSchema.parse(event)).toEqual(event);
		}
	});

	test('rejects legacy invalidation, unknown members, invalid ranges, and catalog authority mismatch', () => {
		const authority = {
			applicationSourceGeneration: 7,
			worktreeId: 'worktree-1',
		} as const;
		const controlChanged = {
			authority,
			kind: 'annotation.controlChanged',
			reason: 'discovery',
		} as const;
		const sessionChanged = {
			authority,
			kind: 'annotation.sessionChanged',
			semanticRevision: 3,
			sessionId: lowercaseSessionId,
		} as const;

		for (const rejected of [
			{
				eventKind: 'snapshot.required',
				operationCorrelationId: 'a'.repeat(64),
				sourceGeneration: 7,
				worktreeId: authority.worktreeId,
			},
			{ ...controlChanged, authority: { ...authority, applicationSourceGeneration: -1 } },
			{ ...controlChanged, authority: { ...authority, applicationSourceGeneration: 1.5 } },
			{ ...controlChanged, authority: { ...authority, worktreeId: '' } },
			{ ...controlChanged, reason: 'unsupported' },
			{ ...controlChanged, payload: { body: 'must not enter metadata' } },
			{ ...sessionChanged, semanticRevision: 0 },
			{ ...sessionChanged, sessionId: 'not-an-annotation-id' },
			{
				authority,
				kind: 'annotation.catalog',
				transfer: {
					catalogRevision: 8,
					expectedEntryCount: 0,
					kind: 'catalog.begin',
					transferId: '01890abc-def0-7abc-8def-012345678900',
				},
			},
		] as const) {
			expect(bridgeProductWorktreeAnnotationEventSchema.safeParse(rejected).success).toBe(false);
		}
	});

	test('models saved content, optional draft, and durable status directly', () => {
		const messageId = '01890abc-def0-7abc-8def-012345678901';
		const threadId = '01890abc-def0-7abc-8def-012345678902';
		const baseMessage = {
			attentionState: 'not_applicable',
			authorKind: 'human',
			createdAtUnixMilliseconds: 1,
			messageId,
			messageRevision: 2,
			ordinal: 0,
			sessionId: lowercaseSessionId,
			sessionRevision: 3,
			status: 'editable',
			handled: false,
			threadId,
			threadRevision: 1,
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
		const newAgentMessage = {
			...savedMessage,
			attentionState: 'new',
			authorKind: 'agent',
		} as const;
		const viewedAgentMessage = {
			...newAgentMessage,
			attentionState: 'viewed',
		} as const;

		for (const message of [
			neverSavedDraft,
			savedMessage,
			savedMessageWithEmptyDraft,
			newAgentMessage,
			viewedAgentMessage,
		]) {
			const { createdAtUnixMilliseconds, ...messageWithoutWireTimestamp } = message;
			expect(bridgeProductWorktreeAnnotationMessageEntrySchema.parse(message)).toEqual({
				...messageWithoutWireTimestamp,
				createdAt: createdAtUnixMilliseconds,
			});
		}
		for (const rejected of [
			{ ...baseMessage, draft: null, savedBody: null, savedRevision: null },
			{ ...savedMessage, savedRevision: null },
			{ ...neverSavedDraft, savedRevision: 1 },
			{ ...neverSavedDraft, draft: { ...neverSavedDraft.draft, body: '   ' } },
			{ ...savedMessage, status: 'provisional' },
			{ ...savedMessage, readiness: 'saved' },
			{ ...savedMessage, createdAtUnixMilliseconds: undefined },
			{ ...savedMessage, createdAtUnixMilliseconds: undefined, createdAt: 1 },
			{ ...savedMessage, savedRevision: undefined },
			{ ...savedMessage, handled: undefined },
			{ ...savedMessage, attentionState: undefined },
			{ ...savedMessage, attentionState: 'new' },
			{ ...savedMessage, authorKind: 'agent', attentionState: 'not_applicable' },
			{ ...newAgentMessage, authorKind: 'robot' },
			{ ...newAgentMessage, attentionState: 'unread' },
			{ ...newAgentMessage, draft: savedMessageWithEmptyDraft.draft },
			{ ...newAgentMessage, handled: true },
			{ ...newAgentMessage, savedBody: null, savedRevision: null },
		] as const) {
			expect(bridgeProductWorktreeAnnotationMessageEntrySchema.safeParse(rejected).success).toBe(
				false,
			);
		}
	});

	test('decodes explicit Unix-millisecond output-history timestamps', () => {
		const wireSummary = {
			attemptId: '01890abc-def0-7abc-8def-012345678903',
			canMarkNotHandled: true,
			createdAtUnixMilliseconds: 1_700_000_000_000,
			messageCount: 1,
			outputKind: 'clipboard_markdown',
			repeatedFromAttemptId: null,
			sessionId: lowercaseSessionId,
			state: 'succeeded',
			updatedAtUnixMilliseconds: 1_700_000_000_001,
		} as const;

		expect(bridgeProductWorktreeAnnotationOutputHistorySummarySchema.parse(wireSummary)).toEqual({
			attemptId: wireSummary.attemptId,
			canMarkNotHandled: true,
			createdAt: wireSummary.createdAtUnixMilliseconds,
			messageCount: 1,
			outputKind: 'clipboard_markdown',
			repeatedFromAttemptId: null,
			sessionId: lowercaseSessionId,
			state: 'succeeded',
			updatedAt: wireSummary.updatedAtUnixMilliseconds,
		});
		expect(
			bridgeProductWorktreeAnnotationOutputHistorySummarySchema.safeParse({
				...wireSummary,
				createdAtUnixMilliseconds: undefined,
				createdAt: wireSummary.createdAtUnixMilliseconds,
			}).success,
		).toBe(false);
	});
});
