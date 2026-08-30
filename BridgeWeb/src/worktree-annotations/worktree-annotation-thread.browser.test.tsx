import { act, type ReactElement } from 'react';
import { beforeEach, describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
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
import {
	useWorktreeAnnotationProjection,
	WorktreeAnnotationSurfaceProvider,
} from './worktree-annotation-surface-provider.js';
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
import { WorktreeAnnotationThread } from './worktree-annotation-thread.js';

describe('worktree annotation inline thread', () => {
	beforeEach(async (): Promise<void> => {
		await act(async (): Promise<void> => {
			await userEvent.unhover(document.body);
		});
	});

	test('renders one message directly with the exact compact controls', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Keep the refresh asynchronous.', messageId: rootMessageId }),
		]);

		await expect.element(rendered.getByText('Keep the refresh asynchronous.')).toBeVisible();
		await expect.element(rendered.getByRole('button', { name: 'Edit annotation' })).toBeVisible();
		await expect
			.element(rendered.getByRole('button', { name: 'Reply to annotation thread' }))
			.toBeVisible();
		await expect
			.element(rendered.getByRole('button', { name: 'Resolve annotation thread' }))
			.toBeVisible();
		await expect
			.element(rendered.getByTestId('worktree-annotation-message-pending-status'))
			.toHaveTextContent('Pending');
		const annotationMessage = rendered.getByTestId('worktree-annotation-message').element();
		expect(
			annotationMessage.querySelector('[data-slot="avatar"][aria-label="You"]'),
		).not.toBeNull();
		expect(annotationMessage.getAttribute('aria-label')).toBe('Root annotation by You');
		expect(annotationMessage.textContent).not.toContain('Root annotation');
		expect(annotationMessage.textContent).not.toContain('Saved');
		expect(document.querySelector('[aria-label="Expand 1 annotation"]')).toBeNull();
		expect(rendered.getByRole('button', { name: 'More comment actions' }).all()).toHaveLength(0);
		expect(document.querySelector('[aria-label^="Show source range"]')).toBeNull();
	});

	test('uses quiet rounded action chrome and command-spec tooltip copy', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Action presentation.', messageId: rootMessageId }),
		]);

		const editButton = rendered.getByRole('button', { name: 'Edit annotation' });
		const editCommands = editButton
			.element()
			.closest<HTMLElement>('[aria-label="Annotation commands"]');
		if (editCommands === null) throw new Error('Expected annotation-local commands.');
		expect(editButton.element().classList).not.toContain('rounded-full');
		expect(getComputedStyle(editCommands).opacity).toBe('1');

		await act(async (): Promise<void> => {
			editButton.element().focus();
			await Promise.resolve();
		});
		expect(getComputedStyle(editCommands).opacity).toBe('1');
		expect(editButton.element().getAttribute('data-tooltip')).toBe('Edit annotation (⌃E)');

		const replyButton = rendered.getByRole('button', { name: 'Reply to annotation thread' });
		expect(replyButton.element().getAttribute('data-tooltip')).toBe(
			'Reply to annotation thread (R)',
		);
		await page.screenshot({ path: '../../../tmp/bridgeweb-annotation-action-ownership.png' });
	});

	test('uses success outline only while the thread can be resolved', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		const message = makeSavedMessage({ body: 'Resolution style.', messageId: rootMessageId });

		await publishThreadMessages(surface, [message]);
		const resolveButton = rendered.getByRole('button', { name: 'Resolve annotation thread' });
		expect(resolveButton.element().classList).toContain('border-success/50');
		expect(resolveButton.element().classList).toContain('text-success');

		await publishThreadMessages(surface, [message], {
			...locatedContext,
			resolution: 'resolved',
		});
		const reopenButton = rendered.getByRole('button', { name: 'Reopen annotation thread' });
		expect(reopenButton.element().classList).toContain('border-border');
		expect(reopenButton.element().classList).not.toContain('border-success/50');

		await publishThreadMessages(surface, [message]);
		expect(
			rendered
				.getByRole('button', { name: 'Resolve annotation thread' })
				.element()
				.classList.contains('border-success/50'),
		).toBe(true);
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

		await expect.element(rendered.getByText('Agent response.')).toBeVisible();
		expect(
			rendered
				.getByTestId('worktree-annotation-message')
				.element()
				.querySelector('[data-slot="avatar"][aria-label="Agent"]'),
		).not.toBeNull();
		const newStatus = rendered.getByTestId('worktree-annotation-message-new-status');
		await expect.element(newStatus).toHaveTextContent('New');
		expect(newStatus.element().className).toContain('text-primary');
		expect(rendered.getByRole('button', { name: 'Edit annotation' }).all()).toHaveLength(0);
		await expect
			.element(rendered.getByRole('button', { name: 'Reply to annotation thread' }))
			.toBeVisible();
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
		).toContain('2 annotations');
		await expect
			.element(rendered.getByRole('button', { name: 'Expand 2 annotations' }))
			.toBeVisible();
		const compactFrame = rendered.getByTestId('worktree-annotation-thread').element();

		const expandButton = rendered.getByRole('button', { name: 'Expand 2 annotations' }).element();
		await act(async (): Promise<void> => {
			await userEvent.click(expandButton);
			await userEvent.unhover(expandButton);
		});

		await expect.element(rendered.getByText('Keep the refresh asynchronous.')).toBeVisible();
		expect(rendered.getByText('Add coverage for the failure case.').all()).toHaveLength(1);
		expect(
			compactFrame.querySelectorAll('[data-testid="worktree-annotation-message"]'),
		).toHaveLength(2);
		await expect
			.element(rendered.getByRole('button', { name: 'Collapse 2 annotations' }))
			.toBeVisible();

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Edit annotation' }).last().click();
		});
		expect(compactFrame.getAttribute('data-annotation-expanded')).toBe('true');
		await act(async (): Promise<void> => {
			rendered.getByRole('textbox', { name: 'Annotation Markdown' }).element().focus();
			await userEvent.keyboard('{Escape}');
		});
		expect(compactFrame.getAttribute('data-annotation-expanded')).toBe('true');
	});

	test('keeps thread actions singular and exposes Edit on every editable annotation', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Editable root.', messageId: rootMessageId }),
			makeSavedMessage({ body: 'Editable reply.', messageId: replyMessageId, ordinal: 1 }),
		]);
		const expandButton = rendered.getByRole('button', { name: 'Expand 2 annotations' }).element();
		await act(async (): Promise<void> => {
			await userEvent.click(expandButton);
			await userEvent.unhover(expandButton);
		});
		await settleThreadMotion(
			rendered.getByTestId('worktree-annotation-thread-history').element(),
			'Expected shortcut-test annotation expansion to settle.',
		);

		expect(rendered.getByRole('button', { name: 'Reply to annotation thread' }).all()).toHaveLength(
			1,
		);
		expect(rendered.getByRole('button', { name: 'Resolve annotation thread' }).all()).toHaveLength(
			1,
		);
		expect(rendered.getByRole('button', { name: 'Edit annotation' }).all()).toHaveLength(2);
		expect(document.body.textContent).not.toContain('•••');
	});

	test.each([
		{ expectedBody: 'Shortcut root.', ordinal: 0 },
		{ expectedBody: 'Shortcut reply.', ordinal: 1 },
	])(
		'routes Control-E to the exact pointer-activated editable annotation',
		async ({ expectedBody, ordinal }) => {
			const surface = new RecordingAnnotationBrowserSurface('fileView');
			const rendered = await renderLocatedAnnotationProjection(surface);
			await publishThreadMessages(surface, [
				makeSavedMessage({ body: 'Shortcut root.', messageId: rootMessageId }),
				makeSavedMessage({ body: 'Shortcut reply.', messageId: replyMessageId, ordinal: 1 }),
			]);
			await act(async (): Promise<void> => {
				await rendered.getByRole('button', { name: 'Expand 2 annotations' }).click();
			});
			await settleThreadMotion(
				rendered.getByTestId('worktree-annotation-thread-history').element(),
				'Expected Edit-shortcut annotation expansion to settle.',
			);
			const targetAnnotation = rendered.getByTestId('worktree-annotation-message').all()[ordinal];
			if (targetAnnotation === undefined)
				throw new Error('Expected the shortcut annotation entry.');
			expect(targetAnnotation.element().getAttribute('tabindex')).toBe('-1');

			await act(async (): Promise<void> => {
				await userEvent.click(rendered.getByText(expectedBody).element());
				await userEvent.keyboard('e');
			});
			expect(rendered.getByRole('textbox', { name: 'Annotation Markdown' }).query()).toBeNull();
			await act(async (): Promise<void> => {
				await userEvent.keyboard('{Control>}e{/Control}');
			});
			await expect
				.element(rendered.getByRole('textbox', { name: 'Annotation Markdown' }))
				.toHaveValue(expectedBody);
		},
	);

	test('does not guess an Edit target after thread-only pointer activation', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderLocatedAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Thread-only shortcut target.', messageId: rootMessageId }),
		]);
		const annotationFrame = rendered.getByTestId('worktree-annotation-thread').element();
		const annotationFrameBounds = annotationFrame.getBoundingClientRect();
		const paddingClickPosition = { x: 4, y: 4 } as const;
		expect(
			document.elementFromPoint(
				annotationFrameBounds.left + paddingClickPosition.x,
				annotationFrameBounds.top + paddingClickPosition.y,
			),
		).toBe(annotationFrame);

		await act(async (): Promise<void> => {
			await userEvent.click(annotationFrame, { position: paddingClickPosition });
		});
		await act(async (): Promise<void> => {
			await userEvent.keyboard('{Control>}e{/Control}');
		});

		expect(rendered.getByRole('textbox', { name: 'Annotation Markdown' }).query()).toBeNull();
	});

	test.each(['r', '{Control>}r{/Control}'])(
		'routes %s after a pointer activates the annotation frame',
		async (keys) => {
			const surface = new RecordingAnnotationBrowserSurface('fileView');
			const rendered = await renderLocatedAnnotationProjection(surface);
			await publishThreadMessages(surface, [
				makeSavedMessage({ body: 'Reply shortcut target.', messageId: rootMessageId }),
			]);
			const annotationFrame = rendered.getByTestId('worktree-annotation-thread').element();
			if (!(annotationFrame instanceof HTMLElement)) throw new Error('Expected annotation frame.');

			await act(async (): Promise<void> => {
				annotationFrame.click();
			});
			expect(annotationFrame.contains(document.activeElement)).toBe(true);
			await act(async (): Promise<void> => {
				await userEvent.keyboard(keys);
			});
			await expect
				.element(rendered.getByRole('textbox', { name: 'Reply with Markdown' }))
				.toBeVisible();
		},
	);

	test('keeps the newly clicked message active after the previous thread flushes', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderLocatedAnnotationProjection(surface);
		const secondThreadContext = {
			...locatedContext,
			endLine: 12,
			startLine: 12,
			threadId: annotationBaseThreadId,
		};
		await publishThreads(surface, [
			{
				context: locatedContext,
				messages: [makeSavedMessage({ body: 'First active thread.', messageId: rootMessageId })],
			},
			{
				context: secondThreadContext,
				messages: [
					makeSavedMessage({
						body: 'Second exact target.',
						messageId: secondRootMessageId,
						threadId: annotationBaseThreadId,
					}),
				],
			},
		]);
		const firstThreadFrame = document.querySelector<HTMLElement>(
			`[data-annotation-thread-id="${CSS.escape(locatedContext.threadId)}"]`,
		);
		const replyToFirstThread = firstThreadFrame?.querySelector<HTMLButtonElement>(
			'button[aria-label="Reply to annotation thread"]',
		);
		if (replyToFirstThread === null || replyToFirstThread === undefined) {
			throw new Error('Expected thread A Reply control.');
		}
		await act(async (): Promise<void> => {
			replyToFirstThread.click();
			await rendered.getByRole('textbox', { name: 'Reply with Markdown' }).fill('Draft in A.');
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'reply.create'),
			'Expected the first thread draft command to remain in flight.',
		);

		await act(async (): Promise<void> => {
			await userEvent.click(rendered.getByText('Second exact target.').element());
		});
		expect(
			document
				.querySelector(`[data-annotation-thread-id="${annotationBaseThreadId}"]`)
				?.getAttribute('data-annotation-active'),
		).toBe('true');

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted();
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean => document.querySelector('[aria-label="Reply with Markdown"]') === null,
			'Expected the first thread editor to finish after its durable flush.',
		);
		expect(
			document
				.querySelector(`[data-annotation-thread-id="${annotationBaseThreadId}"]`)
				?.getAttribute('data-annotation-active'),
		).toBe('true');

		await act(async (): Promise<void> => {
			await userEvent.keyboard('{Control>}e{/Control}');
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Annotation Markdown' }))
			.toHaveValue('Second exact target.');
	});

	test('does not route annotation shortcuts while an editor owns text input', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderLocatedAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Text-input guard.', messageId: rootMessageId }),
		]);
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Reply to annotation thread' }).click();
		});
		const composer = rendered.getByRole('textbox', { name: 'Reply with Markdown' });
		await act(async (): Promise<void> => {
			composer.element().focus();
			await userEvent.keyboard('er{Control>}e{/Control}{Control>}r{/Control}');
		});
		await expect.element(composer).toHaveValue('er');
		expect(rendered.getByRole('textbox', { name: 'Annotation Markdown' }).all()).toHaveLength(0);
		expect(rendered.getByRole('textbox', { name: 'Reply with Markdown' }).all()).toHaveLength(1);
	});

	test('does not route annotation shortcuts while source text is selected', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderLocatedAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Selected annotation text.', messageId: rootMessageId }),
		]);
		const targetAnnotation = rendered.getByTestId('worktree-annotation-message');
		const selectedText = rendered.getByText('Selected annotation text.').element();
		const selectionRange = document.createRange();
		selectionRange.selectNodeContents(selectedText);

		await act(async (): Promise<void> => {
			targetAnnotation.element().focus();
			window.getSelection()?.removeAllRanges();
			window.getSelection()?.addRange(selectionRange);
			await userEvent.keyboard('er');
		});
		expect(rendered.getByRole('textbox', { name: 'Annotation Markdown' }).all()).toHaveLength(0);
		expect(rendered.getByRole('textbox', { name: 'Reply with Markdown' }).all()).toHaveLength(0);
		window.getSelection()?.removeAllRanges();
	});

	test('does not route annotation shortcuts from content-editable or menu owners', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderLocatedAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Owned shortcut targets.', messageId: rootMessageId }),
		]);
		const targetAnnotation = rendered.getByTestId('worktree-annotation-message').element();
		const contentEditableTarget = document.createElement('div');
		contentEditableTarget.contentEditable = 'true';
		contentEditableTarget.tabIndex = 0;
		const menuTarget = document.createElement('div');
		menuTarget.role = 'menu';
		menuTarget.tabIndex = 0;
		targetAnnotation.append(contentEditableTarget, menuTarget);

		for (const ownedTarget of [contentEditableTarget, menuTarget]) {
			await act(async (): Promise<void> => {
				ownedTarget.focus();
				await userEvent.keyboard('er{Control>}e{/Control}{Control>}r{/Control}');
			});
		}
		expect(rendered.getByRole('textbox', { name: 'Annotation Markdown' }).all()).toHaveLength(0);
		expect(rendered.getByRole('textbox', { name: 'Reply with Markdown' }).all()).toHaveLength(0);
		contentEditableTarget.remove();
		menuTarget.remove();
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
		const messageIndex = summaryText?.indexOf('2 annotations') ?? -1;
		expect(newIndex).toBeGreaterThanOrEqual(0);
		expect(pendingIndex).toBeGreaterThan(newIndex);
		expect(messageIndex).toBeGreaterThan(pendingIndex);

		const expandButton = rendered.getByRole('button', { name: 'Expand 2 annotations' }).element();
		await act(async (): Promise<void> => {
			await userEvent.click(expandButton);
			await userEvent.unhover(expandButton);
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
			await rendered.getByRole('button', { name: 'Expand 2 annotations' }).click();
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
			await threads[0]?.getByRole('button', { name: 'Expand 2 annotations' }).click();
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
			thirdFrame.querySelector<HTMLButtonElement>('[aria-label="Expand 2 annotations"]')?.click();
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

	test('distinguishes the neutral Draft cue from yellow Pending state', async () => {
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
		await expect
			.element(rendered.getByTestId('worktree-annotation-message').getByText('Draft'))
			.toBeVisible();
		const draftCue = rendered.getByTestId('worktree-annotation-thread-summary').getByText('Draft');
		await expect.element(draftCue).toBeVisible();
		expect(draftCue.element().className).not.toContain('text-warning');
		expect(document.querySelector('[data-annotation-draft="present"] .bg-warning')).toBeNull();
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

	test('keeps unchanged saved annotations unsaveable without exposing draft internals', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Unchanged saved body.', messageId: rootMessageId }),
		]);

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Edit annotation' }).click();
		});
		const editor = rendered.getByRole('textbox', { name: 'Annotation Markdown' });
		const saveButton = rendered.getByRole('button', { name: 'Save annotation' });
		await expect.element(editor).toHaveValue('Unchanged saved body.');
		await expect.element(editor).toBeEnabled();
		await expect.element(saveButton).toBeDisabled();
		expect(
			surface.sentOperations.some((operation) => operation.kind === 'draft.edit.acquire'),
		).toBe(false);
		const operationCountBeforeShortcut = surface.sentOperations.length;

		await act(async (): Promise<void> => {
			editor.element().focus();
			await userEvent.keyboard('{Meta>}{Enter}{/Meta}');
			await Promise.resolve();
		});
		expect(surface.sentOperations).toHaveLength(operationCountBeforeShortcut);
		expect(document.body.textContent).not.toContain('No durable draft');

		await act(async (): Promise<void> => {
			await editor.fill('Changed saved body.');
		});
		await expect.element(saveButton).toBeEnabled();
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'draft.flush'),
			'Expected the first changed edit to create a durable draft.',
		);
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted();
			await Promise.resolve();
		});
	});

	test('anchors Reply to the shared tooltip and shows the editor focus surface', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Tooltip body.', messageId: rootMessageId }),
		]);

		const replyButton = rendered.getByRole('button', { name: 'Reply to annotation thread' });
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
			await rendered.getByRole('button', { name: 'Edit annotation' }).click();
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

		const expand = rendered.getByRole('button', { name: 'Expand 2 annotations' });
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
			.getByRole('button', { name: 'Reply to annotation thread' })
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
});

function LocatedAnnotationProjection(): ReactElement | null {
	const projection = useWorktreeAnnotationProjection();
	return projection.threads.length === 0 ? null : (
		<>
			{projection.threads.map((thread) => (
				<WorktreeAnnotationThread
					key={thread.context.threadId}
					rangeIdentity={{ itemId: 'file:item-source', range: { end: 7, start: 7 } }}
					thread={thread}
				/>
			))}
		</>
	);
}

async function renderLocatedAnnotationProjection(
	surface: RecordingAnnotationBrowserSurface,
): Promise<Awaited<ReturnType<typeof render>>> {
	return await render(
		<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
			<LocatedAnnotationProjection />
		</WorktreeAnnotationSurfaceProvider>,
	);
}
