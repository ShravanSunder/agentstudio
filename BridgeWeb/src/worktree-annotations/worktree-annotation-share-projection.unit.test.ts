import { describe, expect, test } from 'vitest';

import { deriveWorktreeAnnotationShareProjection } from './worktree-annotation-share-projection.js';

describe('worktree annotation Share projection', () => {
	test('filters pending human messages at message granularity and excludes agent attention', () => {
		const projection = deriveWorktreeAnnotationShareProjection({
			scope: 'new',
			threads: [
				threadFixture('thread-a', 'exact', [
					messageFixture('handled-root', { handled: true }),
					messageFixture('new-locked', { handled: false, status: 'locked' }),
					messageFixture('draft-reply', { draft: { body: 'editing' }, handled: false }),
					messageFixture('agent-unseen', { authorKind: 'agent', handled: false }),
				]),
				threadFixture('thread-b', 'relocated', [messageFixture('handled-only', { handled: true })]),
			],
		});

		expect(projection.newCount).toBe(1);
		expect(projection.allCount).toBe(4);
		expect(projection.inlineThreads).toHaveLength(1);
		expect(projection.inlineThreads[0]?.messages.map((message) => message.messageId)).toEqual([
			'new-locked',
		]);
		expect(projection.otherThreads).toEqual([]);
	});

	test('includes every current saved body under All and routes unplaced threads to Other', () => {
		const projection = deriveWorktreeAnnotationShareProjection({
			scope: 'all',
			threads: [
				threadFixture('thread-a', 'exact', [
					messageFixture('handled-root', { handled: true }),
					messageFixture('new-reply', { handled: false }),
				]),
				threadFixture('thread-b', 'outdated', [
					messageFixture('outdated-locked', { handled: true, status: 'locked' }),
				]),
				threadFixture('thread-c', 'unavailable', [
					messageFixture('unavailable-new', { handled: false }),
				]),
			],
		});

		expect(projection.newCount).toBe(2);
		expect(projection.allCount).toBe(4);
		expect(projection.inlineThreads[0]?.messages.map((message) => message.messageId)).toEqual([
			'handled-root',
			'new-reply',
		]);
		expect(projection.otherThreads.map((thread) => thread.context.threadId)).toEqual([
			'thread-b',
			'thread-c',
		]);
	});

	test('excludes draft-bearing prior saved bodies from New and All', () => {
		const draftMessage = messageFixture('draft-over-saved', {
			draft: { body: 'unsaved edit' },
			handled: false,
		});

		for (const scope of ['new', 'all'] as const) {
			const projection = deriveWorktreeAnnotationShareProjection({
				scope,
				threads: [threadFixture('thread-a', 'exact', [draftMessage])],
			});

			expect(projection.inlineThreads).toEqual([]);
			expect(projection.otherThreads).toEqual([]);
			expect(projection.newCount).toBe(0);
			expect(projection.allCount).toBe(0);
		}
	});
});

interface MessageFixture {
	readonly attentionState: 'new' | 'not_applicable' | 'viewed';
	readonly authorKind: 'agent' | 'human';
	readonly draft: { readonly body: string } | null;
	readonly handled: boolean;
	readonly messageId: string;
	readonly messageRevision: number;
	readonly savedBody: string | null;
	readonly savedRevision: number | null;
	readonly sessionId: string;
	readonly sessionRevision: number;
	readonly status: 'editable' | 'locked';
}

function messageFixture(
	messageId: string,
	overrides: Partial<Omit<MessageFixture, 'messageId'>> = {},
): MessageFixture {
	return {
		attentionState: 'not_applicable',
		authorKind: 'human',
		draft: null,
		handled: false,
		messageId,
		messageRevision: 1,
		savedBody: `Saved body for ${messageId}`,
		savedRevision: 1,
		sessionId: 'session-1',
		sessionRevision: 1,
		status: 'editable',
		...overrides,
	};
}

function threadFixture(
	threadId: string,
	placement: 'exact' | 'outdated' | 'relocated' | 'unavailable',
	messages: readonly MessageFixture[],
): {
	readonly context: {
		readonly path: string;
		readonly placement: 'exact' | 'outdated' | 'relocated' | 'unavailable';
		readonly startLine: number;
		readonly threadId: string;
	};
	readonly messages: readonly MessageFixture[];
} {
	return {
		context: { path: `Sources/${threadId}.swift`, placement, startLine: 1, threadId },
		messages,
	};
}
