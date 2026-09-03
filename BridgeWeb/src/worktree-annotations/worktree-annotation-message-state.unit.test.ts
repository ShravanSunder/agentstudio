import { describe, expect, test } from 'vitest';

import {
	deriveWorktreeAnnotationMessageState,
	deriveWorktreeAnnotationThreadStateCounts,
} from './worktree-annotation-message-state.js';

describe('worktree annotation message state', () => {
	test.each([
		{
			expected: { isAllEligible: true, isNew: false, isPending: true },
			message: messageFacts(),
			name: 'human saved unhandled',
		},
		{
			expected: { isAllEligible: true, isNew: false, isPending: false },
			message: messageFacts({ handled: true }),
			name: 'human handled',
		},
		{
			expected: { isAllEligible: false, isNew: false, isPending: false },
			message: messageFacts({ draft: {} }),
			name: 'human draft',
		},
		{
			expected: { isAllEligible: false, isNew: false, isPending: false },
			message: messageFacts({ savedRevision: null }),
			name: 'missing current saved revision',
		},
		{
			expected: { isAllEligible: true, isNew: true, isPending: false },
			message: messageFacts({ attentionState: 'new', authorKind: 'agent' }),
			name: 'agent new',
		},
		{
			expected: { isAllEligible: true, isNew: false, isPending: false },
			message: messageFacts({ attentionState: 'viewed', authorKind: 'agent' }),
			name: 'agent viewed',
		},
	])('derives $name', ({ expected, message }) => {
		expect(deriveWorktreeAnnotationMessageState(message)).toEqual(expected);
	});

	test('counts independent New and Pending states in projection order', () => {
		const counts = deriveWorktreeAnnotationThreadStateCounts([
			messageFacts({ attentionState: 'new', authorKind: 'agent' }),
			messageFacts(),
			messageFacts({ attentionState: 'viewed', authorKind: 'agent' }),
			messageFacts({ handled: true }),
		]);

		expect(counts).toEqual({ newCount: 1, pendingCount: 1 });
	});

	test('omits both state counts when every current revision is cleared', () => {
		expect(
			deriveWorktreeAnnotationThreadStateCounts([
				messageFacts({ handled: true }),
				messageFacts({ attentionState: 'viewed', authorKind: 'agent' }),
			]),
		).toEqual({ newCount: 0, pendingCount: 0 });
	});
});

interface MessageFacts {
	readonly attentionState: 'new' | 'not_applicable' | 'viewed';
	readonly authorKind: 'agent' | 'human';
	readonly draft: object | null;
	readonly handled: boolean;
	readonly savedBody: string | null;
	readonly savedRevision: number | null;
}

function messageFacts(overrides: Partial<MessageFacts> = {}): MessageFacts {
	return {
		attentionState: 'not_applicable',
		authorKind: 'human',
		draft: null,
		handled: false,
		savedBody: 'Saved body',
		savedRevision: 1,
		...overrides,
	};
}
