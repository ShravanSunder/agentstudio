import { describe, expect, test } from 'vitest';

import type { WorktreeAnnotationCommandOutcome } from './worktree-annotation-surface-client.js';
import {
	WorktreeAnnotationViewedController,
	type WorktreeAnnotationViewedMessage,
} from './worktree-annotation-viewed-controller.js';

const sessionId = '00000000-0000-7000-8000-000000000011';

describe('WorktreeAnnotationViewedController', () => {
	test('partitions 257 exact New pairs sequentially at 256', async () => {
		const calls: number[] = [];
		const controller = new WorktreeAnnotationViewedController(async (operation) => {
			calls.push(operation.items.length);
			return viewedOutcome(operation.items, 8);
		});
		const result = await controller.markMessagesViewed(sessionId, messages(257));

		expect(calls).toEqual([256, 1]);
		expect(result.failedGroupCount).toBe(0);
		expect(controller.presentMessage(requiredMessage(messages(1), 0)).attentionState).toBe(
			'viewed',
		);
	});

	test('continues after a failed middle group and overlays exact successes only', async () => {
		let call = 0;
		const controller = new WorktreeAnnotationViewedController(async (operation) => {
			call += 1;
			if (call === 2) throw new Error('lost response');
			return viewedOutcome(operation.items, 10 + call);
		});
		const allMessages = messages(513);
		const result = await controller.markMessagesViewed(sessionId, allMessages);

		expect(call).toBe(3);
		expect(result.failedGroupCount).toBe(1);
		expect(controller.presentMessage(requiredMessage(allMessages, 0)).attentionState).toBe(
			'viewed',
		);
		expect(controller.presentMessage(requiredMessage(allMessages, 256)).attentionState).toBe('new');
		expect(controller.presentMessage(requiredMessage(allMessages, 512)).attentionState).toBe(
			'viewed',
		);
	});

	test('coalesces identical in-flight revisions and rejects reordered result groups', async () => {
		let resolveOutcome: ((outcome: WorktreeAnnotationCommandOutcome) => void) | undefined;
		let callCount = 0;
		const controller = new WorktreeAnnotationViewedController(
			(operation) =>
				new Promise((resolve): void => {
					callCount += 1;
					resolveOutcome = resolve;
					if (operation.items.length > 1) {
						resolve(viewedOutcome(operation.items.toReversed(), 8));
					}
				}),
		);
		const oneMessage = messages(1);
		const first = controller.markMessagesViewed(sessionId, oneMessage);
		const second = controller.markMessagesViewed(sessionId, oneMessage);
		expect(callCount).toBe(1);
		resolveOutcome?.(
			viewedOutcome(
				[{ expectedSavedRevision: 1, messageId: requiredMessage(oneMessage, 0).messageId }],
				8,
			),
		);
		await Promise.all([first, second]);
		expect(callCount).toBe(1);

		const reorderedMessages = messages(2).map((message) => ({ ...message, savedRevision: 2 }));
		const reorderedResult = await controller.markMessagesViewed(sessionId, reorderedMessages);
		expect(reorderedResult.failedGroupCount).toBe(1);
		expect(controller.presentMessage(requiredMessage(reorderedMessages, 0)).attentionState).toBe(
			'new',
		);
		const wrongSessionController = new WorktreeAnnotationViewedController(async (operation) => ({
			...viewedOutcome(operation.items, 9),
			sessionId: '00000000-0000-7000-8000-000000000099',
		}));
		const wrongSessionResult = await wrongSessionController.markMessagesViewed(
			sessionId,
			oneMessage,
		);
		expect(wrongSessionResult.failedGroupCount).toBe(1);
		expect(
			wrongSessionController.presentMessage(requiredMessage(oneMessage, 0)).attentionState,
		).toBe('new');
	});

	test('keeps contradictory same-revision New fenced and releases on convergence or replacement', async () => {
		const original = requiredMessage(messages(1), 0);
		const controller = new WorktreeAnnotationViewedController(async (operation) =>
			viewedOutcome(operation.items, 9),
		);
		await controller.markMessagesViewed(sessionId, [original]);

		expect(controller.isOutputReady(sessionId, 8, [original])).toBe(false);
		expect(controller.isOutputReady(sessionId, 9, [original])).toBe(false);
		expect(controller.presentMessage(original).attentionState).toBe('viewed');
		controller.reconcileProjection(sessionId, 9, [original]);
		expect(controller.isOutputReady(sessionId, 9, [original])).toBe(false);
		const converged = { ...original, attentionState: 'viewed' as const, sessionRevision: 9 };
		controller.reconcileProjection(sessionId, 9, [converged]);
		expect(controller.isOutputReady(sessionId, 9, [converged])).toBe(true);
		const replaced = { ...original, savedRevision: 2, sessionRevision: 10 };
		expect(controller.presentMessage(replaced).attentionState).toBe('new');
		expect(controller.isOutputReady(sessionId, 10, [replaced])).toBe(true);
		controller.dispose();
		expect(controller.presentMessage(original).attentionState).toBe('new');
	});
});

function messages(count: number): WorktreeAnnotationViewedMessage[] {
	return Array.from({ length: count }, (_, index) => ({
		attentionState: 'new' as const,
		authorKind: 'agent' as const,
		messageId: `00000000-0000-7000-8000-${index.toString(16).padStart(12, '0')}`,
		savedBody: 'Agent',
		savedRevision: 1,
		sessionId,
		sessionRevision: 1,
	}));
}

function viewedOutcome(
	items: readonly { readonly expectedSavedRevision: number; readonly messageId: string }[],
	committedSessionRevision: number,
): WorktreeAnnotationCommandOutcome {
	return {
		receipt: undefined,
		requestId: 'viewed-test',
		sessionId,
		status: {
			kind: 'viewed' as const,
			results: items.map((item) => ({
				committedSessionRevision,
				disposition: 'changed' as const,
				kind: 'viewed' as const,
				messageId: item.messageId,
				savedRevision: item.expectedSavedRevision,
			})),
		},
		surface: 'file' as const,
	};
}

function requiredMessage(
	availableMessages: readonly WorktreeAnnotationViewedMessage[],
	index: number,
): WorktreeAnnotationViewedMessage {
	const message = availableMessages[index];
	if (message === undefined) throw new Error(`Missing viewed test message ${index}.`);
	return message;
}
