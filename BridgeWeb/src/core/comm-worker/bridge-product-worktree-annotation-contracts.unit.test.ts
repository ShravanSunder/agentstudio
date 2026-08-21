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

	test('accepts only the compact snapshot-required invalidation', () => {
		const event = {
			eventKind: 'snapshot.required',
			operationCorrelationId: 'a'.repeat(64),
			sourceGeneration: 7,
			worktreeId: '00000000-0000-7000-8000-000000000001',
		} as const;

		expect(bridgeProductWorktreeAnnotationEventSchema.parse(event)).toEqual(event);
	});

	test('rejects missing, invalid, and unknown invalidation members', () => {
		const event = {
			eventKind: 'snapshot.required',
			operationCorrelationId: 'a'.repeat(64),
			sourceGeneration: 7,
			worktreeId: '00000000-0000-7000-8000-000000000001',
		} as const;
		const { sourceGeneration: _sourceGeneration, ...missingSourceGeneration } = event;
		const { worktreeId: _worktreeId, ...missingWorktreeId } = event;

		for (const rejected of [
			missingSourceGeneration,
			missingWorktreeId,
			{ ...event, eventKind: 'projection.state' },
			{ ...event, eventKind: 'message.batch' },
			{ ...event, sourceGeneration: -1 },
			{ ...event, sourceGeneration: Number.MAX_SAFE_INTEGER + 1 },
			{ ...event, sourceGeneration: 1.5 },
			{ ...event, worktreeId: '' },
			{ ...event, worktreeId: 'x'.repeat(129) },
			{ ...event, worktreeId: 'worktree with spaces' },
			{ ...event, payload: { body: 'must not enter metadata' } },
		] as const) {
			expect(bridgeProductWorktreeAnnotationEventSchema.safeParse(rejected).success).toBe(false);
		}
	});

	test('models saved content, optional draft, and durable status directly', () => {
		const messageId = '01890abc-def0-7abc-8def-012345678901';
		const threadId = '01890abc-def0-7abc-8def-012345678902';
		const baseMessage = {
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

		for (const message of [neverSavedDraft, savedMessage, savedMessageWithEmptyDraft]) {
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
