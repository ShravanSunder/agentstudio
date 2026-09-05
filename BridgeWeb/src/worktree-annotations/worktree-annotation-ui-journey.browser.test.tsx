import { act } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup } from 'vitest-browser-react';
import { page, userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import {
	annotationHeadThreadId,
	annotationSessionId,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import {
	finishJourneyMotion,
	journeyOpenContext,
	journeyOutputAttemptId,
	journeyReplyMessageId,
	journeyResolvedContext,
	journeyRootMessageId,
	makeJourneyReplyDraft,
	makeJourneyRootDraft,
	makeJourneySavedReply,
	makeJourneySavedRoot,
	publishJourneyThread,
	renderWorktreeAnnotationUiJourney,
	settleJourneyInteraction,
	waitForJourneyCondition,
} from './worktree-annotation-ui-journey.browser.test-support.js';

describe('worktree annotation synthetic end-user journey', () => {
	afterEach(async (): Promise<void> => {
		await act(async (): Promise<void> => {
			await cleanup();
			await Promise.resolve();
		});
	});

	test('edits, saves, replies, resolves, reopens, shares, and restores focus', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await renderWorktreeAnnotationUiJourney(surface);
		const initialDraft = makeJourneyRootDraft('persisted-journey-edit', 1);
		await publishJourneyThread({
			context: journeyOpenContext,
			messages: [initialDraft],
			revision: 3,
			surface,
		});

		await performJourneyAction(() =>
			clickButton(rendered.getByRole('button', { name: 'Edit annotation' }).element()),
		);
		await waitForOperation(surface, 'draft.edit.acquire');
		const editAcquire = requireOperation(surface, 'draft.edit.acquire');
		if (editAcquire.kind !== 'draft.edit.acquire') {
			throw new Error('Expected the saved draft edit ownership operation.');
		}
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted(annotationSessionId, 1);
			surface.publishThread({
				context: journeyOpenContext,
				message: makeJourneyRootDraft(editAcquire.editToken, 2),
			});
			await settleJourneyInteraction();
		});
		const rootEditor = rendered.getByRole('textbox', { name: 'Annotation Markdown' });
		await expect.element(rootEditor).toBeEnabled();
		expect(document.activeElement).toBe(rootEditor.element());
		expect(rootEditor.element().getBoundingClientRect().height).toBeGreaterThanOrEqual(48);
		await performJourneyAction(() =>
			rootEditor.fill('Clarify the reconnect state before enabling Share.'),
		);
		await page.screenshot({
			element: rendered.getByTestId('worktree-annotation-ui-journey').element(),
			path: '../../../tmp/worktree-annotation-ui-journey-editing.png',
		});

		await performJourneyAction(() =>
			clickButton(rendered.getByRole('button', { name: 'Save annotation' }).element()),
		);
		await waitForOperation(surface, 'draft.flush', journeyRootMessageId);
		expect(requireOperation(surface, 'draft.flush')).toMatchObject({
			body: 'Clarify the reconnect state before enabling Share.',
			messageId: journeyRootMessageId,
		});
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'draft.flush');
			await settleJourneyInteraction();
		});
		await waitForOperation(surface, 'draft.save');
		expect(requireOperation(surface, 'draft.save')).toMatchObject({
			messageId: journeyRootMessageId,
		});
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'draft.save');
			await settleJourneyInteraction();
		});
		await waitForJourneyCondition(
			() => document.querySelector('[aria-label="Annotation Markdown"]') === null,
			'Expected the committed Save receipt to close the root editor.',
		);
		const thread = rendered.getByTestId('worktree-annotation-thread').element();
		expect(thread.contains(document.activeElement)).toBe(true);

		const savedRoot = makeJourneySavedRoot(5);
		await publishJourneyThread({
			context: journeyOpenContext,
			messages: [savedRoot],
			revision: 5,
			surface,
		});
		await expect
			.element(rendered.getByText('Clarify the reconnect state before enabling Share.'))
			.toBeVisible();
		await page.screenshot({
			element: rendered.getByTestId('worktree-annotation-ui-journey').element(),
			path: '../../../tmp/worktree-annotation-ui-journey-saved.png',
		});

		await performJourneyAction(() => userEvent.keyboard('{Control>}r{/Control}'));
		const replyEditor = rendered.getByRole('textbox', { name: 'Reply with Markdown' });
		await expect.element(replyEditor).toBeVisible();
		expect(document.activeElement).toBe(replyEditor.element());
		await performJourneyAction(() => userEvent.keyboard('{Tab}'));
		expect(document.activeElement).not.toBe(replyEditor.element());
		await performJourneyAction(() => userEvent.keyboard('{Shift>}{Tab}{/Shift}'));
		expect(document.activeElement).toBe(replyEditor.element());
		await performJourneyAction(() =>
			replyEditor.fill('Added the readiness guard and recovery coverage.'),
		);
		await waitForOperation(surface, 'reply.create');
		const replyCreate = requireOperation(surface, 'reply.create');
		if (replyCreate.kind !== 'reply.create') {
			throw new Error('Expected the reply draft creation operation.');
		}
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted(annotationSessionId, 1);
			await settleJourneyInteraction();
		});
		const replyDraft = makeJourneyReplyDraft(replyCreate.editToken, 6);
		await publishJourneyThread({
			context: journeyOpenContext,
			messages: [savedRoot, replyDraft],
			revision: 6,
			surface,
		});
		await performJourneyAction(() =>
			clickButton(rendered.getByRole('button', { name: 'Save annotation' }).element()),
		);
		await waitForOperation(surface, 'draft.save', journeyReplyMessageId);
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'draft.save');
			await settleJourneyInteraction();
		});
		await expect
			.element(rendered.getByTestId('worktree-annotation-committed-pending-projection'))
			.toBeVisible();

		const savedReply = makeJourneySavedReply(7);
		await publishJourneyThread({
			context: journeyOpenContext,
			messages: [savedRoot, savedReply],
			revision: 7,
			surface,
		});
		await expect
			.element(rendered.getByText('Added the readiness guard and recovery coverage.'))
			.toBeVisible();
		expect(rendered.getByTestId('worktree-annotation-message').all()).toHaveLength(2);
		await page.screenshot({
			element: rendered.getByTestId('worktree-annotation-ui-journey').element(),
			path: '../../../tmp/worktree-annotation-ui-journey-replied.png',
		});

		await performJourneyAction(() =>
			clickButton(rendered.getByRole('button', { name: 'Resolve annotation thread' }).element()),
		);
		await waitForOperation(surface, 'thread.resolution.set');
		expect(requireOperation(surface, 'thread.resolution.set')).toMatchObject({
			resolution: 'resolved',
			threadId: annotationHeadThreadId,
		});
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommittedWithoutProjection(
				annotationSessionId,
				'thread.resolution.set',
			);
			await settleJourneyInteraction();
		});
		await publishJourneyThread({
			context: journeyResolvedContext,
			messages: [savedRoot, savedReply],
			revision: 8,
			surface,
		});
		expect(thread.getAttribute('data-annotation-resolution')).toBe('resolved');
		await expect
			.element(rendered.getByRole('button', { name: 'Reopen annotation thread' }))
			.toBeVisible();
		await page.screenshot({
			element: rendered.getByTestId('worktree-annotation-ui-journey').element(),
			path: '../../../tmp/worktree-annotation-ui-journey-resolved.png',
		});

		await performJourneyAction(() =>
			clickButton(rendered.getByRole('button', { name: 'Reopen annotation thread' }).element()),
		);
		await waitForOperationCount(surface, 'thread.resolution.set', 2);
		expect(requireOperation(surface, 'thread.resolution.set')).toMatchObject({
			resolution: 'open',
		});
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommittedWithoutProjection(
				annotationSessionId,
				'thread.resolution.set',
			);
			await settleJourneyInteraction();
		});
		await publishJourneyThread({
			context: journeyOpenContext,
			messages: [savedRoot, savedReply],
			revision: 9,
			surface,
		});
		expect(thread.getAttribute('data-annotation-resolution')).toBe('open');

		const shareTrigger = rendered.getByRole('button', { name: 'Share comments' });
		await performJourneyAction(() => clickButton(shareTrigger.element()));
		const shareShelf = rendered.getByTestId('worktree-annotation-share-shelf').element();
		if (!(shareShelf instanceof HTMLElement)) throw new Error('Expected the Share shelf.');
		await finishJourneyMotion(shareShelf);
		const viewportBounds = rendered
			.getByTestId('worktree-annotation-ui-journey-viewport')
			.element()
			.getBoundingClientRect();
		const shelfBounds = shareShelf.getBoundingClientRect();
		expect(shelfBounds.right).toBeLessThanOrEqual(viewportBounds.right);
		expect(shelfBounds.top).toBeGreaterThanOrEqual(viewportBounds.top);
		await expect
			.element(rendered.getByRole('button', { name: 'Pending comments, 1' }))
			.toBeVisible();
		await performJourneyAction(() =>
			clickButton(rendered.getByRole('button', { name: 'All comments, 2' }).element()),
		);
		expect(
			rendered
				.getByRole('button', { name: 'All comments, 2' })
				.element()
				.getAttribute('aria-pressed'),
		).toBe('true');
		await page.screenshot({
			element: rendered.getByTestId('worktree-annotation-ui-journey').element(),
			path: '../../../tmp/worktree-annotation-ui-journey-share.png',
		});

		await performJourneyAction(() =>
			clickButton(rendered.getByRole('button', { name: 'Copy Markdown' }).element()),
		);
		await waitForOperation(surface, 'output.scope.commit');
		expect(requireOperation(surface, 'output.scope.commit')).toMatchObject({
			kind: 'output.scope.commit',
			outputKind: 'clipboardMarkdown',
			scope: 'all',
		});
		await act(async (): Promise<void> => {
			surface.settleMostRecentOutput({
				kind: 'succeeded',
				summary: {
					attemptId: journeyOutputAttemptId,
					destinationFilename: null,
					messageCount: 2,
					outputKind: 'clipboard_markdown',
					sessionId: annotationSessionId,
				},
			});
			await settleJourneyInteraction();
		});
		await finishJourneyMotion(shareShelf);
		await expect
			.element(rendered.getByRole('region', { name: 'Share comments' }))
			.not.toBeInTheDocument();
		expect(document.activeElement).toBe(shareTrigger.element());
		await expect.element(rendered.getByText('Copied 2 annotations')).toBeVisible();
		await expect
			.element(rendered.getByRole('button', { name: 'Mark as not handled' }))
			.toBeVisible();

		await performJourneyAction(() => clickButton(shareTrigger.element()));
		await expect.element(rendered.getByRole('region', { name: 'Share comments' })).toBeVisible();
		const reopenedShareShelf = rendered.getByTestId('worktree-annotation-share-shelf').element();
		if (!(reopenedShareShelf instanceof HTMLElement)) {
			throw new Error('Expected the reopened Share shelf.');
		}
		await performJourneyAction(() => userEvent.keyboard('{Escape}'));
		await finishJourneyMotion(reopenedShareShelf);
		await expect
			.element(rendered.getByRole('region', { name: 'Share comments' }))
			.not.toBeInTheDocument();
		expect(document.activeElement).toBe(shareTrigger.element());
	});
});

type JourneyOperationKind = BridgeProductWorktreeAnnotationOperation['kind'];

async function performJourneyAction(action: () => Promise<void> | void): Promise<void> {
	await act(async (): Promise<void> => {
		await action();
		await settleJourneyInteraction();
	});
}

async function clickButton(element: HTMLElement | SVGElement): Promise<void> {
	if (!(element instanceof HTMLButtonElement)) throw new Error('Expected an HTML button.');
	await userEvent.click(element);
	await userEvent.unhover(element);
}

async function waitForOperation(
	surface: RecordingAnnotationBrowserSurface,
	kind: JourneyOperationKind,
	messageId?: string,
): Promise<void> {
	await waitForJourneyCondition(
		() =>
			surface.sentOperations.some(
				(operation) =>
					operation.kind === kind &&
					(messageId === undefined ||
						('messageId' in operation && operation.messageId === messageId)),
			),
		`Expected ${kind} from the production annotation UI.`,
	);
}

async function waitForOperationCount(
	surface: RecordingAnnotationBrowserSurface,
	kind: JourneyOperationKind,
	count: number,
): Promise<void> {
	await waitForJourneyCondition(
		() => surface.sentOperations.filter((operation) => operation.kind === kind).length >= count,
		`Expected ${count} ${kind} operations from the production annotation UI.`,
	);
}

function requireOperation(
	surface: RecordingAnnotationBrowserSurface,
	kind: JourneyOperationKind,
): BridgeProductWorktreeAnnotationOperation {
	const operation = surface.sentOperations.findLast((candidate) => candidate.kind === kind);
	if (operation === undefined) throw new Error(`Expected ${kind} operation.`);
	return operation;
}
