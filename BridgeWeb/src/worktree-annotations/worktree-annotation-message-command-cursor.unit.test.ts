import { describe, expect, test } from 'vitest';

import {
	newestMessageCommandCursor,
	type WorktreeAnnotationMessageCommandCursor,
} from './worktree-annotation-message-command-cursor.js';

describe('newestMessageCommandCursor', () => {
	const currentCursor = {
		draftRevision: null,
		messageId: 'message-1',
		messageRevision: 3,
		savedRevision: 2,
		sessionId: 'session-1',
		sessionRevision: 5,
		threadId: 'thread-1',
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
