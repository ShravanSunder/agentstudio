import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { userEvent } from 'vitest/browser';

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
	useWorktreeAnnotationProjection,
	WorktreeAnnotationSurfaceProvider,
} from './worktree-annotation-surface-provider.js';
import { WorktreeAnnotationThread } from './worktree-annotation-thread.js';

describe('worktree annotation inline thread', () => {
	test('renders one message directly without a disclosure control', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);

		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Keep the refresh asynchronous.', messageId: rootMessageId }),
		]);

		await expect.element(rendered.getByText('Keep the refresh asynchronous.')).toBeVisible();
		expect(document.querySelector('[aria-label^="Expand "]')).toBeNull();
	});

	test('collapses multiple messages to the latest summary and expands once in flat order', async () => {
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
		await expect.element(rendered.getByRole('button', { name: 'Expand 2 messages' })).toBeVisible();

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Expand 2 messages' }).click();
		});

		await expect.element(rendered.getByText('Keep the refresh asynchronous.')).toBeVisible();
		await expect.element(rendered.getByText('Add coverage for the failure case.')).toBeVisible();
		await expect
			.element(rendered.getByRole('button', { name: 'Collapse 2 messages' }))
			.toBeVisible();
		expect(document.querySelectorAll('[data-testid="worktree-annotation-message"]')).toHaveLength(
			2,
		);
	});

	test('keeps disclosure independent for same-coordinate threads', async () => {
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

	test('reverts a durable reply draft instead of only hiding its composer', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
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
			surface.publishThread({ context: locatedContext, message: root });
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
						body: 'Durable reply',
						revision: 1,
					},
					savedBody: null,
					savedRevision: null,
				},
			});
			await Promise.resolve();
		});
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

	test('persists an empty draft while editing an already saved message', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		const savedMessage = makeSavedMessage({ body: 'Saved body.', messageId: rootMessageId });

		await publishThreadMessages(surface, [savedMessage]);
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Edit annotation' }).click();
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

	test('supports keyboard disclosure and forces authoring expansion until empty Escape', async () => {
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
		expect(document.activeElement).toBe(
			rendered.getByRole('button', { name: 'Collapse 2 messages' }).element(),
		);

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Reply to thread' }).click();
		});
		const composer = rendered.getByRole('textbox', { name: 'Reply with Markdown' });
		await expect.element(composer).toBeVisible();
		await expect
			.element(rendered.getByRole('button', { name: 'Collapse 2 messages' }))
			.toBeDisabled();

		await act(async (): Promise<void> => {
			composer.element().focus();
			await userEvent.keyboard('{Escape}');
		});
		expect(document.querySelector('[aria-label="Reply with Markdown"]')).toBeNull();
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

async function renderAnnotationProjection(
	surface: RecordingAnnotationBrowserSurface,
): Promise<Awaited<ReturnType<typeof render>>> {
	return await render(
		<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
			<AnnotationProjection />
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
	await act(async (): Promise<void> => {
		surface.publishProjectionState({
			revision: 3,
			sessions: [annotationSessionSummary({ revision: 3, sessionId: annotationSessionId })],
		});
		for (const thread of threads) {
			for (const message of thread.messages) {
				surface.publishThread({ context: thread.context, message });
			}
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
