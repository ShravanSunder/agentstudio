import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { userEvent } from 'vitest/browser';

import {
	createBridgeMarkdownRenderWorkerClient,
	type BridgeMarkdownRenderWorkerClient,
} from '../app/markdown/worker/bridge-markdown-render-worker-client.js';
import { buildBridgeMarkdownRenderWorkerSuccessResponse } from '../app/markdown/worker/bridge-markdown-render-worker-renderer.js';
import type { BridgeMarkdownRenderWorkerRequest } from '../app/markdown/worker/bridge-markdown-render-worker-rpc.js';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
	annotationBaseThreadId,
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationThreadContext,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationActiveEditTokens,
	useWorktreeAnnotationEditSurfaceToken,
	useWorktreeAnnotationProjection,
	WorktreeAnnotationSurfaceProvider,
} from './worktree-annotation-surface-provider.js';
import {
	WorktreeAnnotationNewMessageComposer,
	WorktreeAnnotationThread,
} from './worktree-annotation-thread.js';

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
		expect(document.querySelector('[aria-label="Expand 1 message"]')).toBeNull();
		expect(rendered.getByRole('button', { name: 'More comment actions' }).all()).toHaveLength(0);
		expect(document.querySelector('[aria-label^="Show source range"]')).toBeNull();
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

	test('reverts a durable reply draft instead of only hiding its composer', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderRemountingAnnotationProjection(surface);
		const root = makeSavedMessage({ body: 'Root body.', messageId: rootMessageId });

		await publishThreadMessages(surface, [root]);
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Reply to thread' }).click();
			await rendered.getByRole('textbox', { name: 'Reply with Markdown' }).fill('Durable reply');
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'reply.create'),
			'Expected the first reply edit to create a durable draft.',
		);
		const createOperation = surface.sentOperations.find(
			(operation) => operation.kind === 'reply.create',
		);
		if (createOperation?.kind !== 'reply.create') throw new Error('Expected reply.create.');

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted();
			await Promise.resolve();
		});
		await act(async (): Promise<void> => {
			surface.publishThreadMessages({
				context: locatedContext,
				messages: [
					{ ...root, sessionRevision: 4 },
					{
						...annotationMessage({
							messageId: secondRootMessageId,
							ordinal: 1,
							sessionRevision: 4,
							threadId: annotationHeadThreadId,
						}),
						draft: {
							activeEditToken: createOperation.editToken,
							body: 'Durable reply',
							revision: 1,
						},
						savedBody: null,
						savedRevision: null,
					},
				],
			});
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean => document.body.textContent?.includes('saved locally') ?? false,
			'Expected the remounted composer to adopt its durable reply draft.',
		);
		await expect.element(rendered.getByText('saved locally')).toBeVisible();

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Revert draft' }).click();
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'draft.revert'),
			'Expected Revert to issue draft.revert.',
		);
		expect(surface.sentOperations.at(-1)).toMatchObject({
			kind: 'draft.revert',
			messageId: secondRootMessageId,
		});
	});

	test('adopts durable detail that arrives after the composer remounts', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const editToken = 'annotation-edit-remounted-reply';
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<ProjectionRemountingReplyComposer editToken={editToken} />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 0,
				revision: 3,
				sessions: [annotationSessionSummary({ revision: 3, sessionId: annotationSessionId })],
			});
			await rendered.getByRole('textbox', { name: 'Reply with Markdown' }).fill('Durable reply');
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'reply.create'),
			'Expected the first reply edit to create a durable draft.',
		);

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted(annotationSessionId, 1);
			await Promise.resolve();
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Reply with Markdown' }))
			.toHaveValue('Durable reply');

		await act(async (): Promise<void> => {
			surface.publishThread({
				context: locatedContext,
				message: {
					...annotationMessage({
						messageId: secondRootMessageId,
						ordinal: 1,
						sessionRevision: 4,
						threadId: annotationHeadThreadId,
					}),
					draft: { activeEditToken: editToken, body: 'Durable reply', revision: 1 },
					savedBody: null,
					savedRevision: null,
				},
			});
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean => document.body.textContent?.includes('saved locally') ?? false,
			'Expected the surviving composer to adopt delayed durable detail.',
		);
		await expect
			.element(rendered.getByRole('textbox', { name: 'Reply with Markdown' }))
			.toHaveValue('Durable reply');
		expect(document.querySelectorAll('[aria-label="Reply with Markdown"]')).toHaveLength(1);
	});

	test('completes the first Save across a durable projection remount', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const editToken = 'annotation-edit-save-across-remount';
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<ProjectionRemountingReplyComposer editToken={editToken} />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 0,
				revision: 3,
				sessions: [annotationSessionSummary({ revision: 3, sessionId: annotationSessionId })],
			});
			await rendered
				.getByRole('textbox', { name: 'Reply with Markdown' })
				.fill('Save across replacement');
			await rendered.getByRole('button', { name: 'Save annotation' }).click();
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'reply.create'),
			'Expected first Save to create the durable reply draft.',
		);
		const createOperation = surface.sentOperations.find(
			(operation) => operation.kind === 'reply.create',
		);
		if (createOperation?.kind !== 'reply.create') throw new Error('Expected reply.create.');

		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted(annotationSessionId, 1);
			surface.publishThread({
				context: locatedContext,
				message: {
					...annotationMessage({
						messageId: secondRootMessageId,
						ordinal: 1,
						sessionRevision: 4,
						threadId: annotationHeadThreadId,
					}),
					draft: {
						activeEditToken: createOperation.editToken,
						body: 'Save across replacement',
						revision: 0,
					},
					savedBody: null,
					savedRevision: null,
				},
			});
			await Promise.resolve();
		});
		await settleBrowserCondition(
			(): boolean => surface.sentOperations.some((operation) => operation.kind === 'draft.save'),
			'Expected the original Save action to continue after the Pierre portal remount.',
		);
		expect(
			surface.sentOperations
				.map((operation) => operation.kind)
				.filter((kind) => kind !== 'session.discover'),
		).toEqual(['demand.acquire', 'source.refresh', 'output.history', 'reply.create', 'draft.save']);
		await act(async (): Promise<void> => {
			surface.settleMostRecentCommitted(annotationSessionId, 1);
			surface.publishThread({
				context: locatedContext,
				message: {
					...annotationMessage({
						messageId: secondRootMessageId,
						ordinal: 1,
						sessionRevision: 5,
						threadId: annotationHeadThreadId,
					}),
					draft: null,
					savedBody: 'Save across replacement',
					savedRevision: 1,
				},
			});
			await Promise.resolve();
		});
		await expect.element(rendered.getByRole('button', { name: 'Save annotation' })).toBeVisible();
	});

	test('keeps an edit token active until every overlapping composer unregisters', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const editToken = 'annotation-edit-overlapping-portals';
		const rendered = await render(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<ComposerRegistrationFixture editToken={editToken} registrationCount={2} />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await expect
			.element(rendered.getByTestId('active-composer-edit-token'))
			.toHaveTextContent(editToken);

		await rendered.rerender(
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				<ComposerRegistrationFixture editToken={editToken} registrationCount={1} />
			</WorktreeAnnotationSurfaceProvider>,
		);
		await expect
			.element(rendered.getByTestId('active-composer-edit-token'))
			.toHaveTextContent(editToken);
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
	});

	test('persists an empty draft while editing an already saved message', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		const savedMessage = makeSavedMessage({ body: 'Saved body.', messageId: rootMessageId });

		await publishThreadMessages(surface, [savedMessage]);
		await act(async (): Promise<void> => {
			await rendered.getByText('Saved body.').click();
			await rendered.getByRole('textbox', { name: 'Annotation Markdown' }).fill('');
			rendered.getByRole('textbox', { name: 'Annotation Markdown' }).element().blur();
		});
		await settleBrowserCondition(
			(): boolean =>
				surface.sentOperations.some(
					(operation) => operation.kind === 'draft.flush' && operation.body === '',
				),
			'Expected focus loss to persist the empty saved-message draft.',
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
			'Expected focus-loss persistence to close the saved-message editor.',
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

function AnnotationProjection(): ReactElement | null {
	const projection = useWorktreeAnnotationProjection();
	return projection.threads.length === 0 ? null : (
		<>
			{projection.threads.map((thread) => (
				<WorktreeAnnotationThread key={thread.context.threadId} thread={thread} />
			))}
		</>
	);
}

function RemountingAnnotationProjection(): ReactElement | null {
	const projection = useWorktreeAnnotationProjection();
	return projection.threads.length === 0 ? null : (
		<>
			{projection.threads.map((thread) => (
				<WorktreeAnnotationThread
					key={`${thread.context.threadId}:${projection.revision}`}
					thread={thread}
				/>
			))}
		</>
	);
}

function ProjectionRemountingReplyComposer(props: { readonly editToken: string }): ReactElement {
	const projection = useWorktreeAnnotationProjection();
	return (
		<WorktreeAnnotationNewMessageComposer
			createOperation={(body, editToken) => ({
				body,
				editToken,
				expectedThreadRevision: 3,
				kind: 'reply.create',
				sessionId: annotationSessionId,
				threadId: annotationHeadThreadId,
			})}
			editToken={props.editToken}
			key={projection.revision}
			onCancel={() => {}}
			onSaved={() => {}}
			placement="embedded"
			placeholder="Reply with Markdown"
		/>
	);
}

function ComposerRegistrationFixture(props: {
	readonly editToken: string;
	readonly registrationCount: 1 | 2;
}): ReactElement {
	const activeEditTokens = useWorktreeAnnotationActiveEditTokens();
	return (
		<>
			<ComposerRegistration editToken={props.editToken} />
			{props.registrationCount === 2 ? <ComposerRegistration editToken={props.editToken} /> : null}
			<span data-testid="active-composer-edit-token">
				{activeEditTokens.has(props.editToken) ? props.editToken : 'inactive'}
			</span>
		</>
	);
}

function ComposerRegistration(props: { readonly editToken: string }): null {
	useWorktreeAnnotationEditSurfaceToken(props.editToken);
	return null;
}

async function renderAnnotationProjection(
	surface: RecordingAnnotationBrowserSurface,
	markdownWorkerClient?: BridgeMarkdownRenderWorkerClient,
): Promise<Awaited<ReturnType<typeof render>>> {
	return await render(
		<WorktreeAnnotationSurfaceProvider
			markdownWorkerClient={markdownWorkerClient}
			surfaceClient={surface.client}
		>
			<AnnotationProjection />
		</WorktreeAnnotationSurfaceProvider>,
	);
}

async function renderRemountingAnnotationProjection(
	surface: RecordingAnnotationBrowserSurface,
): Promise<Awaited<ReturnType<typeof render>>> {
	return await render(
		<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
			<RemountingAnnotationProjection />
		</WorktreeAnnotationSurfaceProvider>,
	);
}

async function publishThreadMessages(
	surface: RecordingAnnotationBrowserSurface,
	messages: readonly WorktreeAnnotationMessageEntry[],
	context: WorktreeAnnotationThreadContext = locatedContext,
): Promise<void> {
	await publishThreads(surface, [{ context, messages }]);
}

async function publishThreads(
	surface: RecordingAnnotationBrowserSurface,
	threads: readonly {
		readonly context: WorktreeAnnotationThreadContext;
		readonly messages: readonly WorktreeAnnotationMessageEntry[];
	}[],
): Promise<void> {
	const eligibleMessageCount = threads.reduce(
		(count, thread): number =>
			count +
			thread.messages.filter(
				(message): boolean =>
					message.savedBody !== null && message.draft === null && message.status === 'editable',
			).length,
		0,
	);
	await act(async (): Promise<void> => {
		surface.publishProjectionState({
			expectedThreadCount: threads.length,
			revision: 3,
			sessions: [
				annotationSessionSummary({
					eligibleMessageCount,
					revision: 3,
					sessionId: annotationSessionId,
				}),
			],
		});
		for (const thread of threads) {
			surface.publishThreadMessages({ context: thread.context, messages: thread.messages });
		}
		await Promise.resolve();
	});
}

function makeSavedMessage(props: {
	readonly body: string;
	readonly messageId: string;
	readonly ordinal?: number;
	readonly threadId?: string;
}): WorktreeAnnotationMessageEntry {
	return {
		...annotationMessage({
			messageId: props.messageId,
			...(props.ordinal === undefined ? {} : { ordinal: props.ordinal }),
			sessionRevision: 3,
			threadId: props.threadId ?? annotationHeadThreadId,
		}),
		createdAt: Date.now() / 1000 - 978_307_200 - (props.ordinal ?? 0) * 60,
		savedBody: props.body,
	};
}

const locatedContext: WorktreeAnnotationThreadContext = {
	diffSide: null,
	endLine: 7,
	path: 'Sources/App/View.swift',
	placement: 'exact',
	resolution: 'open',
	scope: 'located',
	sourceIdentity: 'descriptor-file-1',
	sourceRole: 'file',
	startLine: 4,
	threadId: annotationHeadThreadId,
};

const rootMessageId = '00000000-0000-7000-8000-000000000091';
const replyMessageId = '00000000-0000-7000-8000-000000000092';
const secondRootMessageId = '00000000-0000-7000-8000-000000000093';
const secondReplyMessageId = '00000000-0000-7000-8000-000000000094';
const thirdReplyMessageId = '00000000-0000-7000-8000-000000000096';

async function settleBrowserCondition(
	predicate: () => boolean,
	failureMessage: string,
	remainingFrames = 60,
): Promise<void> {
	await act(async (): Promise<void> => {
		await Promise.resolve();
		await new Promise<void>((resolve): void => {
			requestAnimationFrame((): void => resolve());
		});
		await Promise.resolve();
	});
	if (predicate()) return;
	if (remainingFrames <= 0) throw new Error(failureMessage);
	await settleBrowserCondition(predicate, failureMessage, remainingFrames - 1);
}

function createDeferred<TValue>(): {
	readonly promise: Promise<TValue>;
	readonly reject: (error: Error) => void;
	readonly resolve: (value: TValue) => void;
} {
	let reject!: (error: Error) => void;
	let resolve!: (value: TValue) => void;
	const promise = new Promise<TValue>((promiseResolve, promiseReject): void => {
		resolve = promiseResolve;
		reject = promiseReject;
	});
	return { promise, reject, resolve };
}
