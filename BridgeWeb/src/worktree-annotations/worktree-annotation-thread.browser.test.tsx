import { act } from 'react';
import { describe, expect, test } from 'vitest';
import { page, userEvent } from 'vitest/browser';

import { createBridgeMarkdownRenderWorkerClient } from '../app/markdown/worker/bridge-markdown-render-worker-client.js';
import { buildBridgeMarkdownRenderWorkerSuccessResponse } from '../app/markdown/worker/bridge-markdown-render-worker-renderer.js';
import type { BridgeMarkdownRenderWorkerRequest } from '../app/markdown/worker/bridge-markdown-render-worker-rpc.js';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
	annotationBaseThreadId,
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import type { WorktreeAnnotationMessageEntry } from './worktree-annotation-surface-client.js';
import {
	createDeferred,
	locatedContext,
	makeSavedMessage,
	publishThreadMessages,
	publishThreads,
	renderAnnotationProjection,
	replyMessageId,
	rootMessageId,
	secondReplyMessageId,
	secondRootMessageId,
	settleBrowserCondition,
	settleThreadMotion,
	thirdReplyMessageId,
} from './worktree-annotation-thread.browser.test-support.js';

describe('worktree annotation inline thread', () => {
	test('renders one message directly with the exact compact controls', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Keep the refresh asynchronous.', messageId: rootMessageId }),
		]);

		await expect.element(rendered.getByText('Keep the refresh asynchronous.')).toBeVisible();
		await expect.element(rendered.getByRole('button', { name: 'Edit annotation' })).toBeVisible();
		await expect.element(rendered.getByRole('button', { name: 'Reply to thread' })).toBeVisible();
		await expect.element(rendered.getByRole('button', { name: 'Resolve thread' })).toBeVisible();
		await expect.element(rendered.getByLabelText('You')).toBeVisible();
		await expect
			.element(rendered.getByTestId('worktree-annotation-message-pending-status'))
			.toHaveTextContent('Pending');
		expect(document.querySelector('[aria-label="Expand 1 message"]')).toBeNull();
		expect(rendered.getByRole('button', { name: 'More comment actions' }).all()).toHaveLength(0);
		expect(document.querySelector('[aria-label^="Show source range"]')).toBeNull();
	});

	test('renders a one-message agent thread as New and read-only while retaining Reply', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		const agentMessage = {
			...makeSavedMessage({ body: 'Agent response.', messageId: rootMessageId }),
			attentionState: 'new',
			authorKind: 'agent',
		} as const;

		await publishThreadMessages(surface, [agentMessage]);

		await expect.element(rendered.getByLabelText('Agent')).toBeVisible();
		await expect.element(rendered.getByText('Agent response.')).toBeVisible();
		const newStatus = rendered.getByTestId('worktree-annotation-message-new-status');
		await expect.element(newStatus).toHaveTextContent('New');
		expect(newStatus.element().className).toContain('text-primary');
		expect(rendered.getByRole('button', { name: 'Edit annotation' }).all()).toHaveLength(0);
		await expect.element(rendered.getByRole('button', { name: 'Reply to thread' })).toBeVisible();
		const agentMessageSurface = rendered.getByText('Agent response.').element();
		agentMessageSurface.focus();
		expect(
			surface.sentOperations.filter((operation) => operation.kind === 'message.viewed.mark'),
		).toHaveLength(0);
		await rendered.getByText('Agent response.').click();
		expect(document.querySelector('[aria-label="Annotation Markdown"]')).toBeNull();
		expect(
			surface.sentOperations.some((operation) => operation.kind === 'draft.edit.acquire'),
		).toBe(false);
		await settleBrowserCondition(
			(): boolean =>
				surface.sentOperations.some((operation) => operation.kind === 'message.viewed.mark'),
			'Expected deliberate agent message activation to issue message.viewed.mark.',
		);
		expect(
			surface.sentOperations.find((operation) => operation.kind === 'message.viewed.mark'),
		).toEqual({
			items: [{ expectedSavedRevision: 1, messageId: rootMessageId }],
			kind: 'message.viewed.mark',
			sessionId: annotationSessionId,
		});
		await act(async (): Promise<void> => {
			surface.settleMostRecentViewed(2);
			await Promise.resolve();
		});
		expect(rendered.getByTestId('worktree-annotation-message-new-status').all()).toHaveLength(0);
	});

	test('renders summary plus latest collapsed and every message once when expanded inline', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({
				body: 'Keep the refresh asynchronous.',
				messageId: rootMessageId,
			}),
			makeSavedMessage({
				body: 'Add coverage for the failure case.',
				messageId: replyMessageId,
				ordinal: 1,
			}),
		]);

		await expect.element(rendered.getByText('Add coverage for the failure case.')).toBeVisible();
		expect(document.body.textContent).not.toContain('Keep the refresh asynchronous.');
		await expect.element(rendered.getByTestId('worktree-annotation-thread-summary')).toBeVisible();
		expect(
			rendered.getByTestId('worktree-annotation-thread-summary').element().textContent,
		).toContain('2 messages');
		await expect.element(rendered.getByRole('button', { name: 'Expand 2 messages' })).toBeVisible();
		const compactFrame = rendered.getByTestId('worktree-annotation-thread').element();

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Expand 2 messages' }).click();
		});

		await expect.element(rendered.getByText('Keep the refresh asynchronous.')).toBeVisible();
		expect(rendered.getByText('Add coverage for the failure case.').all()).toHaveLength(1);
		expect(
			compactFrame.querySelectorAll('[data-testid="worktree-annotation-message"]'),
		).toHaveLength(2);
		await expect
			.element(rendered.getByRole('button', { name: 'Collapse 2 messages' }))
			.toBeVisible();

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Edit annotation' }).click();
		});
		expect(compactFrame.getAttribute('data-annotation-expanded')).toBe('true');
		await act(async (): Promise<void> => {
			rendered.getByRole('textbox', { name: 'Annotation Markdown' }).element().focus();
			await userEvent.keyboard('{Escape}');
		});
		expect(compactFrame.getAttribute('data-annotation-expanded')).toBe('true');
	});

	test('orders nonzero New and Pending counts and reveals their exact messages', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Human pending.', messageId: rootMessageId }),
			{
				...makeSavedMessage({
					body: 'Agent new.',
					messageId: replyMessageId,
					ordinal: 1,
				}),
				attentionState: 'new',
				authorKind: 'agent',
			},
		]);

		const summaryText = rendered
			.getByTestId('worktree-annotation-thread-summary')
			.element().textContent;
		const newIndex = summaryText?.indexOf('1 new') ?? -1;
		const pendingIndex = summaryText?.indexOf('1 pending') ?? -1;
		const messageIndex = summaryText?.indexOf('2 messages') ?? -1;
		expect(newIndex).toBeGreaterThanOrEqual(0);
		expect(pendingIndex).toBeGreaterThan(newIndex);
		expect(messageIndex).toBeGreaterThan(pendingIndex);

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Expand 2 messages' }).click();
		});
		await settleThreadMotion(
			rendered.getByTestId('worktree-annotation-thread-history').element(),
			'Expected New/Pending thread expansion motion to settle.',
		);
		expect(
			surface.sentOperations.filter((operation) => operation.kind === 'message.viewed.mark'),
		).toEqual([
			{
				items: [{ expectedSavedRevision: 1, messageId: replyMessageId }],
				kind: 'message.viewed.mark',
				sessionId: annotationSessionId,
			},
		]);
		await expect.element(rendered.getByText('Human pending.')).toBeVisible();
		await expect.element(rendered.getByText('Agent new.')).toBeVisible();
		expect(rendered.getByTestId('worktree-annotation-message-pending-status').all()).toHaveLength(
			1,
		);
		expect(rendered.getByTestId('worktree-annotation-message-new-status').all()).toHaveLength(1);
		await page.screenshot({ path: '../../../tmp/bridgeweb-new-pending-thread.png' });
	});

	test('preserves the compact Markdown render while adding missing inline messages', async () => {
		const abortedRequestIds: string[] = [];
		const capturedRequests: BridgeMarkdownRenderWorkerRequest[] = [];
		const deferredResponses: Array<ReturnType<typeof createDeferred<unknown>>> = [];
		let nextRequestId = 0;
		const markdownWorkerClient = createBridgeMarkdownRenderWorkerClient({
			createRequestId: (): string => {
				nextRequestId += 1;
				return `annotation-markdown-${nextRequestId}`;
			},
			transport: {
				abort: (request): void => {
					abortedRequestIds.push(request.requestId);
				},
				send: (request): Promise<unknown> => {
					capturedRequests.push(request);
					const deferredResponse = createDeferred<unknown>();
					deferredResponses.push(deferredResponse);
					return deferredResponse.promise;
				},
			},
		});
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface, markdownWorkerClient);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Root Markdown.', messageId: rootMessageId }),
			makeSavedMessage({ body: 'Latest Markdown.', messageId: replyMessageId, ordinal: 1 }),
		]);
		await settleBrowserCondition(
			(): boolean => capturedRequests.length === 1,
			'Expected compact M-last to start one Markdown render.',
		);

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Expand 2 messages' }).click();
		});
		await settleBrowserCondition(
			(): boolean => capturedRequests.length === 2,
			'Expected inline expansion to retain M-last and add only the missing root render.',
		);
		expect(abortedRequestIds).toEqual([]);
		await act(async (): Promise<void> => {
			await Promise.all(
				capturedRequests.map(async (request, index): Promise<void> => {
					deferredResponses[index]?.resolve(
						await buildBridgeMarkdownRenderWorkerSuccessResponse({
							renderMarkdown: async () => ({
								htmlCandidate: `<p>${request.requestId}</p>`,
								mermaidDiagrams: [],
							}),
							request,
						}),
					);
				}),
			);
			await Promise.resolve();
		});
	});

	test('keeps one inline expansion keyed to the selected same-coordinate thread', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreads(surface, [
			{
				context: locatedContext,
				messages: [
					makeSavedMessage({ body: 'Thread A root.', messageId: rootMessageId }),
					makeSavedMessage({
						body: 'Thread A latest.',
						messageId: replyMessageId,
						ordinal: 1,
					}),
				],
			},
			{
				context: { ...locatedContext, threadId: annotationBaseThreadId },
				messages: [
					makeSavedMessage({
						body: 'Thread B root.',
						messageId: secondRootMessageId,
						threadId: annotationBaseThreadId,
					}),
					makeSavedMessage({
						body: 'Thread B latest.',
						messageId: secondReplyMessageId,
						ordinal: 1,
						threadId: annotationBaseThreadId,
					}),
				],
			},
		]);

		const threads = rendered.getByTestId('worktree-annotation-thread').all();
		expect(threads).toHaveLength(2);
		await act(async (): Promise<void> => {
			await threads[0]?.getByRole('button', { name: 'Expand 2 messages' }).click();
		});

		await expect.element(rendered.getByText('Thread A root.')).toBeVisible();
		expect(document.body.textContent).not.toContain('Thread B root.');
		expect(document.querySelectorAll('[data-annotation-expanded="true"]')).toHaveLength(1);
	});

	test('returns focus to the nearest surviving compact thread when the invoker is removed', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		await renderAnnotationProjection(surface);
		const thirdThreadId = '00000000-0000-7000-8000-000000000095';
		const firstThread = {
			context: locatedContext,
			messages: [makeSavedMessage({ body: 'First thread.', messageId: rootMessageId })],
		};
		const secondThread = {
			context: { ...locatedContext, threadId: annotationBaseThreadId },
			messages: [
				makeSavedMessage({
					body: 'Second thread.',
					messageId: secondRootMessageId,
					threadId: annotationBaseThreadId,
				}),
			],
		};
		const thirdThread = {
			context: { ...locatedContext, threadId: thirdThreadId },
			messages: [
				makeSavedMessage({
					body: 'Third thread.',
					messageId: secondReplyMessageId,
					threadId: thirdThreadId,
				}),
				makeSavedMessage({
					body: 'Third thread latest.',
					messageId: thirdReplyMessageId,
					ordinal: 1,
					threadId: thirdThreadId,
				}),
			],
		};
		await publishThreads(surface, [firstThread, secondThread, thirdThread]);
		const thirdFrame = document.querySelector<HTMLElement>(
			`[data-annotation-thread-id="${thirdThreadId}"]`,
		);
		if (thirdFrame === null) throw new Error('Expected the third compact thread.');
		await act(async (): Promise<void> => {
			thirdFrame.querySelector<HTMLButtonElement>('[aria-label="Expand 2 messages"]')?.click();
			await Promise.resolve();
		});
		expect(thirdFrame.getAttribute('data-annotation-expanded')).toBe('true');

		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 2,
				revision: 4,
				sessions: [annotationSessionSummary({ revision: 4, sessionId: annotationSessionId })],
			});
			for (const thread of [firstThread, secondThread]) {
				surface.publishThreadMessages({
					context: thread.context,
					messages: thread.messages.map((message) =>
						Object.assign({}, message, { sessionRevision: 4 }),
					),
				});
			}
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean => document.querySelector('[data-annotation-expanded="true"]') === null,
			'Expected removal of the exact thread identity to collapse its inline expansion.',
		);
		const secondFrame = document.querySelector<HTMLElement>(
			`[data-annotation-thread-id="${annotationBaseThreadId}"]`,
		);
		await settleBrowserCondition(
			(): boolean => secondFrame?.contains(document.activeElement) === true,
			'Expected focus to return to the nearest surviving compact thread.',
		);
		expect(secondFrame?.contains(document.activeElement)).toBe(true);
	});

	test('summarizes hidden draft, locked, and relocated thread state', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(
			surface,
			[
				{
					...makeSavedMessage({ body: 'Earlier draft.', messageId: rootMessageId }),
					draft: { activeEditToken: null, body: 'Earlier draft changes.', revision: 2 },
				},
				{
					...makeSavedMessage({
						body: 'Locked reply.',
						messageId: replyMessageId,
						ordinal: 1,
					}),
					status: 'locked',
				},
				makeSavedMessage({
					body: 'Latest reply.',
					messageId: secondRootMessageId,
					ordinal: 2,
				}),
			],
			{ ...locatedContext, placement: 'relocated' },
		);

		await expect.element(rendered.getByText('Latest reply.')).toBeVisible();
		await expect.element(rendered.getByText('Draft')).toBeVisible();
		await expect.element(rendered.getByText('Contains locked output')).toBeVisible();
		await expect.element(rendered.getByText('Relocated')).toBeVisible();
	});

	test('shows the warning Draft cue when the compact latest message has a draft', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Earlier message.', messageId: rootMessageId }),
			{
				...makeSavedMessage({
					body: 'Saved latest message.',
					messageId: replyMessageId,
					ordinal: 1,
				}),
				draft: {
					activeEditToken: null,
					body: 'Unsaved latest changes.',
					revision: 2,
				},
			},
		]);

		await expect.element(rendered.getByText('Unsaved latest changes.')).toBeVisible();
		const draftCue = rendered.getByTestId('worktree-annotation-thread-summary').getByText('Draft');
		await expect.element(draftCue).toBeVisible();
		expect(draftCue.element().className).toContain('text-warning');
	});

	test('keeps output inclusion controls out of the thread timeline', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Earlier included message.', messageId: rootMessageId }),
			makeSavedMessage({ body: 'Latest included message.', messageId: replyMessageId, ordinal: 1 }),
		]);
		expect(document.querySelector('[aria-label="Include latest comment"]')).toBeNull();
		expect(document.querySelector('[aria-label="Exclude latest comment"]')).toBeNull();
		expect(rendered.getByText('Mixed inclusion').all()).toHaveLength(0);
	});

	test('saves a resumed durable draft from the primary pointer action', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		const draftMessage = {
			...makeSavedMessage({ body: 'Saved body.', messageId: rootMessageId }),
			draft: {
				activeEditToken: 'annotation-edit-existing-draft',
				body: 'Reviewed body.',
				revision: 1,
			},
			savedRevision: 1,
		} satisfies WorktreeAnnotationMessageEntry;

		await publishThreadMessages(surface, [draftMessage]);
		await act(async (): Promise<void> => {
			await rendered.getByText('Reviewed body.').click();
		});
		await settleBrowserCondition(
			(): boolean =>
				surface.sentOperations.some((operation) => operation.kind === 'draft.edit.acquire'),
			'Expected the resumed draft to acquire current-generation edit ownership.',
		);
		const acquireOperation = surface.sentOperations.find(
			(operation) => operation.kind === 'draft.edit.acquire',
		);
		if (acquireOperation?.kind !== 'draft.edit.acquire') {
			throw new Error('Expected draft.edit.acquire before Save.');
		}
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted();
			surface.publishThread({
				context: locatedContext,
				message: {
					...draftMessage,
					draft: {
						activeEditToken: acquireOperation.editToken,
						body: 'Reviewed body.',
						revision: 2,
					},
					sessionRevision: 4,
				},
			});
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Save annotation' }).click();
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'draft.save'),
			'Expected the primary Save action to issue draft.save.',
		);
		expect(surface.sentOperations.at(-1)).toMatchObject({
			kind: 'draft.save',
			messageId: rootMessageId,
		});

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'draft.save');
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean => document.querySelector('[aria-label="Annotation Markdown"]') === null,
			'Expected the exact committed Save receipt to close the editor before projection.',
		);
		expect(
			rendered.getByTestId('worktree-annotation-thread').element().contains(document.activeElement),
		).toBe(true);
		expect(
			rendered
				.getByTestId('worktree-annotation-thread')
				.element()
				.getAttribute('data-annotation-expanded'),
		).toBe('true');
		await act(async (): Promise<void> => {
			surface.publishThread({
				context: locatedContext,
				message: {
					...draftMessage,
					draft: null,
					savedBody: 'Reviewed body.',
					savedRevision: 2,
					sessionRevision: 5,
				},
			});
			await Promise.resolve();
		});
		await expect
			.element(rendered.getByTestId('worktree-annotation-thread').getByText('Reviewed body.'))
			.toBeVisible();
		expect(
			rendered.getByTestId('worktree-annotation-thread').element().contains(document.activeElement),
		).toBe(true);
	});

	test('anchors Reply to the shared tooltip and shows the editor focus surface', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Tooltip body.', messageId: rootMessageId }),
		]);

		const replyButton = rendered.getByRole('button', { name: 'Reply to thread' });
		expect(replyButton.element().getAttribute('data-slot')).toBe('tooltip-trigger');

		await act(async (): Promise<void> => {
			await replyButton.click();
		});
		const composer = rendered.getByRole('textbox', { name: 'Reply with Markdown' });
		await expect.element(composer).toBeVisible();
		const focusSurface = composer.element().closest<HTMLElement>('.bg-comment-surface');
		if (focusSurface === null) throw new Error('Expected the shared comment-card focus surface.');
		expect(focusSurface.contains(document.activeElement)).toBe(true);
		expect(getComputedStyle(focusSurface).boxShadow).not.toBe('none');
	});

	test('persists an empty saved-message draft when Escape exits editing', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		const savedMessage = makeSavedMessage({ body: 'Saved body.', messageId: rootMessageId });

		await publishThreadMessages(surface, [savedMessage]);
		await act(async (): Promise<void> => {
			await rendered.getByText('Saved body.').click();
			await rendered.getByRole('textbox', { name: 'Annotation Markdown' }).fill('');
			await userEvent.keyboard('{Escape}');
		});
		await settleBrowserCondition(
			(): boolean =>
				surface.sentOperations.some(
					(operation) => operation.kind === 'draft.flush' && operation.body === '',
				),
			'Expected Escape to persist the empty saved-message draft.',
		);
		const flushOperation = surface.sentOperations.find(
			(operation) => operation.kind === 'draft.flush' && operation.body === '',
		);
		if (flushOperation?.kind !== 'draft.flush') throw new Error('Expected draft.flush.');

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted();
			surface.publishThread({
				context: locatedContext,
				message: {
					...savedMessage,
					draft: { activeEditToken: flushOperation.editToken, body: '', revision: 1 },
					sessionRevision: 4,
				},
			});
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean => document.querySelector('[aria-label="Annotation Markdown"]') === null,
			'Expected Escape persistence to close the saved-message editor.',
		);
		expect(flushOperation.body).toBe('');
	});

	test('supports keyboard inline expansion and two-stage Escape while editing', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Root body.', messageId: rootMessageId }),
			makeSavedMessage({ body: 'Latest body.', messageId: replyMessageId, ordinal: 1 }),
		]);

		const expand = rendered.getByRole('button', { name: 'Expand 2 messages' });
		await act(async (): Promise<void> => {
			expand.element().focus();
			await userEvent.keyboard('{Enter}');
		});
		await expect.element(rendered.getByText('Root body.')).toBeVisible();
		expect(
			rendered
				.getByTestId('worktree-annotation-thread')
				.element()
				.getAttribute('data-annotation-expanded'),
		).toBe('true');

		const replyButtons = rendered
			.getByTestId('worktree-annotation-thread')
			.getByRole('button', { name: 'Reply to thread' })
			.all();
		const latestReplyButton = replyButtons.at(-1);
		if (latestReplyButton === undefined) throw new Error('Expected the latest Reply control.');
		await act(async (): Promise<void> => {
			await latestReplyButton.click();
		});
		const composer = rendered.getByRole('textbox', { name: 'Reply with Markdown' });
		await expect.element(composer).toBeVisible();

		await act(async (): Promise<void> => {
			composer.element().focus();
			await userEvent.keyboard('{Escape}');
		});
		expect(document.querySelector('[aria-label="Reply with Markdown"]')).toBeNull();
		expect(
			rendered
				.getByTestId('worktree-annotation-thread')
				.element()
				.getAttribute('data-annotation-expanded'),
		).toBe('true');

		await act(async (): Promise<void> => {
			await userEvent.keyboard('{Escape}');
		});
		expect(document.querySelector('[data-annotation-expanded="true"]')).toBeNull();
		expect(document.activeElement).toBe(latestReplyButton.element());
	});

	test('flushes the active editor before outside press collapses the inline thread', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Outside-close root.', messageId: rootMessageId }),
		]);
		const replyButton = rendered
			.getByTestId('worktree-annotation-thread')
			.getByRole('button', { name: 'Reply to thread' });
		await act(async (): Promise<void> => {
			await replyButton.click();
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Reply with Markdown' }))
			.toBeVisible();
		await act(async (): Promise<void> => {
			document.body.click();
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean => document.querySelector('[data-annotation-expanded="true"]') === null,
			'Expected outside press to collapse only after the active editor exited.',
		);
	});
});
