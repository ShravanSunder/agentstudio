import { describe, expect, test } from 'vitest';

import {
	messageCommandCursorFromOutcome,
	newestCommandConfirmedThreadRevision,
	newestMessageCommandCursor,
	type WorktreeAnnotationMessageCommandCursor,
} from './worktree-annotation-message-command-cursor.js';
import type { WorktreeAnnotationCommandOutcome } from './worktree-annotation-surface-client.js';

describe('newestMessageCommandCursor', () => {
	const currentCursor = {
		draftRevision: null,
		messageId: 'message-1',
		messageRevision: 3,
		savedRevision: 2,
		sessionId: 'session-1',
		sessionRevision: 5,
		threadId: 'thread-1',
		threadRevision: 2,
	} satisfies WorktreeAnnotationMessageCommandCursor;

	test('retains an exact command receipt when the rendered projection is stale', () => {
		const staleProjectionCursor = {
			...currentCursor,
			draftRevision: 2,
			messageRevision: 2,
			savedRevision: 1,
			sessionRevision: 4,
		} satisfies WorktreeAnnotationMessageCommandCursor;

		expect(newestMessageCommandCursor(currentCursor, staleProjectionCursor)).toBe(currentCursor);
	});

	test('does not replace a newer message receipt with an unrelated session revision', () => {
		const unrelatedSessionAdvance = {
			...currentCursor,
			messageRevision: currentCursor.messageRevision - 1,
			sessionRevision: currentCursor.sessionRevision + 100,
		} satisfies WorktreeAnnotationMessageCommandCursor;

		expect(newestMessageCommandCursor(currentCursor, unrelatedSessionAdvance)).toBe(currentCursor);
	});

	test('advances to a newer projected revision after convergence', () => {
		const convergedProjectionCursor = {
			...currentCursor,
			messageRevision: 4,
			sessionRevision: 6,
		} satisfies WorktreeAnnotationMessageCommandCursor;

		expect(newestMessageCommandCursor(currentCursor, convergedProjectionCursor)).toBe(
			convergedProjectionCursor,
		);
	});
});

describe('messageCommandCursorFromOutcome', () => {
	test('reads every CAS fence from the canonical message', () => {
		const outcome = canonicalMessageOutcome();

		expect(messageCommandCursorFromOutcome(outcome)).toEqual({
			draftRevision: 4,
			messageId: '01890abc-def0-7abc-8def-012345678901',
			messageRevision: 5,
			savedRevision: 3,
			sessionId: '01890abc-def0-7abc-8def-0123456789ab',
			sessionRevision: 7,
			threadId: '01890abc-def0-7abc-8def-012345678902',
			threadRevision: 6,
		});
	});

	test('rejects a removal tombstone rather than manufacturing a message cursor', () => {
		const outcome = canonicalMessageOutcome();
		if (outcome.receipt?.kind !== 'message') throw new Error('Expected canonical message receipt.');
		const removalOutcome: WorktreeAnnotationCommandOutcome = {
			receipt: {
				kind: 'message_removed',
				messageId: outcome.receipt.message.messageId,
				removedMessageRevision: 5,
				sessionId: outcome.receipt.message.sessionId,
				sessionRevision: 8,
				threadId: '01890abc-def0-7abc-8def-012345678902',
				threadRevision: 7,
			},
			requestId: 'cursor-removal-1',
			sessionId: outcome.receipt.message.sessionId,
			status: { kind: 'committed' },
			surface: 'file',
		};

		expect(() => messageCommandCursorFromOutcome(removalOutcome)).toThrow(/message receipt/iu);
		expect(
			newestCommandConfirmedThreadRevision('01890abc-def0-7abc-8def-012345678902', [
				removalOutcome,
			]),
		).toBe(7);
	});
});

function canonicalMessageOutcome(): WorktreeAnnotationCommandOutcome {
	return {
		receipt: {
			context: {
				diffSide: null,
				endLine: 2,
				path: 'Sources/App.swift',
				resolution: 'open',
				scope: 'located',
				sourceIdentity: 'source-1',
				sourceRole: 'file',
				startLine: 2,
				threadId: '01890abc-def0-7abc-8def-012345678902',
			},
			kind: 'message',
			message: {
				attentionState: 'not_applicable',
				authorKind: 'human',
				createdAt: 1,
				draft: { activeEditToken: 'edit-1', body: 'Draft', revision: 4 },
				handled: false,
				messageId: '01890abc-def0-7abc-8def-012345678901',
				messageRevision: 5,
				ordinal: 0,
				savedBody: 'Saved',
				savedRevision: 3,
				sessionId: '01890abc-def0-7abc-8def-0123456789ab',
				sessionRevision: 7,
				status: 'editable',
				threadId: '01890abc-def0-7abc-8def-012345678902',
				threadRevision: 6,
			},
		},
		requestId: 'cursor-command-1',
		sessionId: '01890abc-def0-7abc-8def-0123456789ab',
		status: { kind: 'committed' },
		surface: 'file',
	};
}
