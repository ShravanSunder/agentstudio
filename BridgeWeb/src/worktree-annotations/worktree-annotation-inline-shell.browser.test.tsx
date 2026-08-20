import { act, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';
import { page, userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import {
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

describe('worktree annotation inline shell', () => {
	afterEach(async (): Promise<void> => {
		await cleanup();
	});

	test('expands complete chronology on one inline timeline and moves following content', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderInlineShell(surface);
		await publishTwoMessageThread(surface);
		const visibleLatestMessage = rendered
			.getByTestId('worktree-annotation-thread')
			.getByText('Latest message.');

		await expect.element(visibleLatestMessage).toBeVisible();
		expect(document.body.textContent).not.toContain('Root message.');
		const compactThread = rendered.getByTestId('worktree-annotation-thread').element();
		expect(compactThread.classList).toContain('max-w-3xl');
		expect(compactThread.classList).not.toContain('max-w-xl');
		const followingDiffRow = rendered.getByTestId('following-diff-row').element();
		const compactThreadHeight = compactThread.getBoundingClientRect().height;
		const followingDiffRowTop = followingDiffRow.getBoundingClientRect().top;
		const expandButton = rendered.getByRole('button', { name: 'Expand 2 messages' }).element();
		expect(expandButton.classList).toContain('rounded-md');
		expect(expandButton.classList).not.toContain('rounded-full');
		expect(expandButton.classList).not.toContain('border-comment-border');
		await expect.element(rendered.getByTestId('worktree-annotation-summary-node')).toBeVisible();

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Expand 2 messages' }).click();
			await Promise.resolve();
		});

		const thread = rendered.getByTestId('worktree-annotation-thread').element();
		await expect.element(rendered.getByText('Root message.')).toBeVisible();
		expect(document.querySelector('[data-testid="worktree-annotation-summary-node"]')).toBeNull();
		expect(rendered.getByText('Latest message.').all()).toHaveLength(1);
		const expandedMessages = [
			...thread.querySelectorAll<HTMLElement>('[data-testid="worktree-annotation-message"]'),
		];
		expect(expandedMessages).toHaveLength(2);
		const firstMessageBounds = expandedMessages[0]?.getBoundingClientRect();
		const secondMessageBounds = expandedMessages[1]?.getBoundingClientRect();
		if (firstMessageBounds === undefined || secondMessageBounds === undefined) {
			throw new Error('Expected two measured inline messages.');
		}
		expect(secondMessageBounds.top - firstMessageBounds.bottom).toBeCloseTo(4, 1);
		const latestCommandRail = expandedMessages[1]?.querySelector<HTMLElement>(
			'[aria-label="Comment commands"]',
		);
		const latestCard = latestCommandRail?.parentElement;
		if (
			latestCommandRail === undefined ||
			latestCommandRail === null ||
			latestCard === undefined ||
			latestCard === null
		) {
			throw new Error('Expected the latest message command rail and card.');
		}
		const latestCommandRailBounds = latestCommandRail.getBoundingClientRect();
		const latestCardBounds = latestCard.getBoundingClientRect();
		expect(latestCommandRailBounds.top).toBeGreaterThanOrEqual(latestCardBounds.top);
		expect(latestCommandRailBounds.bottom).toBeLessThanOrEqual(latestCardBounds.bottom);
		expect(compactThread.getBoundingClientRect().height).toBeGreaterThan(compactThreadHeight);
		expect(followingDiffRow.getBoundingClientRect().top).toBeGreaterThan(followingDiffRowTop);
		await page.screenshot({ path: '../../../tmp/bridgeweb-inline-thread-expanded.png' });

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Collapse 2 messages' }).click();
		});
		await settleBrowserCondition(
			(): boolean => !document.body.textContent?.includes('Root message.'),
			'Expected Collapse to restore the compact summary and latest message.',
		);
		await expect.element(visibleLatestMessage).toBeVisible();
		expect(followingDiffRow.getBoundingClientRect().top).toBeCloseTo(followingDiffRowTop, 1);
	});

	test('opens Reply as the next node on the inline timeline and preserves the first edit', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderInlineShell(surface);
		await publishTwoMessageThread(surface);

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Reply to thread' }).click();
		});

		const thread = rendered.getByTestId('worktree-annotation-thread').element();
		const composer = rendered.getByRole('textbox', { name: 'Reply with Markdown' });
		await expect.element(composer).toBeVisible();
		expect(thread.contains(composer.element())).toBe(true);
		await expect.element(rendered.getByText('Root message.')).toBeVisible();

		await act(async (): Promise<void> => {
			await composer.fill('Inline reply draft');
		});
		await expect.element(composer).toHaveValue('Inline reply draft');
		expect(thread.contains(composer.element())).toBe(true);
	});

	test('activates on focus and summary click without expanding the thread', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderInlineShell(surface);
		await publishTwoMessageThread(surface);

		const compactSurface = rendered.getByTestId('worktree-annotation-message');
		await act(async (): Promise<void> => {
			compactSurface.element().focus();
			await Promise.resolve();
		});
		expect(document.body.textContent).not.toContain('Root message.');
		expect(rendered.getByTestId('worktree-annotation-thread').element().classList).toContain(
			'bg-comment-active-surface',
		);

		await act(async (): Promise<void> => {
			await rendered
				.getByTestId('worktree-annotation-thread-summary')
				.getByText('2 messages')
				.click();
			await Promise.resolve();
		});
		expect(document.body.textContent).not.toContain('Root message.');

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Expand 2 messages' }).click();
			await Promise.resolve();
		});
		await expect.element(rendered.getByText('Root message.')).toBeVisible();
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Collapse 2 messages' }).click();
		});
		await settleBrowserCondition(
			(): boolean => !document.body.textContent?.includes('Root message.'),
			'Expected Collapse to restore compact presentation.',
		);
	});

	test('keeps only Reply and primary Resolve in the compact rail and edits from the body', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderInlineShell(surface);
		await publishTwoMessageThread(surface);

		const thread = rendered.getByTestId('worktree-annotation-thread');
		expect(thread.getByRole('button', { name: 'Edit annotation' }).all()).toHaveLength(0);
		await expect.element(thread.getByRole('button', { name: 'Reply to thread' })).toBeVisible();
		const resolveButton = thread.getByRole('button', { name: 'Resolve thread' });
		await expect.element(resolveButton).toBeVisible();
		expect(resolveButton.element().className).toContain('bg-primary/15');

		await act(async (): Promise<void> => {
			await thread.getByText('Latest message.').click();
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Annotation Markdown' }))
			.toBeVisible();
	});

	test('offers Edit in More and supports Enter from message focus', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderInlineShell(surface);
		await publishTwoMessageThread(surface);

		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'More comment actions' }).click();
		});
		await expect.element(rendered.getByRole('button', { name: 'Edit annotation' })).toBeVisible();
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Edit annotation' }).click();
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Annotation Markdown' }))
			.toBeVisible();

		await act(async (): Promise<void> => {
			rendered.getByRole('textbox', { name: 'Annotation Markdown' }).element().focus();
			await userEvent.keyboard('{Escape}');
		});
		const message = rendered.getByTestId('worktree-annotation-message').all().at(-1);
		if (message === undefined) throw new Error('Expected the latest message after editing.');
		await act(async (): Promise<void> => {
			message.element().focus();
			await userEvent.keyboard('{Enter}');
		});
		await expect
			.element(rendered.getByRole('textbox', { name: 'Annotation Markdown' }))
			.toBeVisible();
	});

	test('preserves message links and selected text without entering edit mode', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderInlineShell(surface);
		await publishTwoMessageThread(surface);
		const messageText = rendered.getByText('Latest message.').element();
		const syntheticLink = document.createElement('a');
		syntheticLink.href = 'https://example.com/';
		syntheticLink.textContent = 'Reference';
		syntheticLink.addEventListener('click', (event) => event.preventDefault());
		messageText.append(syntheticLink);

		await act(async (): Promise<void> => {
			syntheticLink.dispatchEvent(new MouseEvent('click', { bubbles: true }));
		});
		expect(document.querySelector('[aria-label="Annotation Markdown"]')).toBeNull();

		const selection = window.getSelection();
		const selectionRange = document.createRange();
		selectionRange.selectNodeContents(messageText);
		selection?.removeAllRanges();
		selection?.addRange(selectionRange);
		await act(async (): Promise<void> => {
			messageText.dispatchEvent(new MouseEvent('click', { bubbles: true }));
		});
		expect(document.querySelector('[aria-label="Annotation Markdown"]')).toBeNull();
		selection?.removeAllRanges();
	});

	test('keeps the max-w-3xl frame contained at narrow width and 200 percent text', async () => {
		const priorRootFontSize = document.documentElement.style.fontSize;
		document.documentElement.style.fontSize = '32px';
		try {
			const surface = new RecordingAnnotationBrowserSurface('fileView');
			const rendered = await renderInlineShell(surface);
			await publishTwoMessageThread(surface);
			const thread = rendered.getByTestId('worktree-annotation-thread').element();
			const host = thread.parentElement;
			if (host === null) throw new Error('Expected the inline-shell host.');
			host.style.width = '360px';
			const hostBounds = host.getBoundingClientRect();
			const threadBounds = thread.getBoundingClientRect();
			expect(getComputedStyle(document.documentElement).fontSize).toBe('32px');
			expect(threadBounds.left).toBeGreaterThanOrEqual(hostBounds.left);
			expect(threadBounds.right).toBeLessThanOrEqual(hostBounds.right);
			expect(document.documentElement.scrollWidth).toBe(document.documentElement.clientWidth);
		} finally {
			document.documentElement.style.fontSize = priorRootFontSize;
		}
	});
});

function InlineShellProjection(): ReactElement | null {
	const projection = useWorktreeAnnotationProjection();
	const thread = projection.threads[0];
	return thread === undefined ? null : (
		<div>
			<WorktreeAnnotationThread
				rangeIdentity={{ itemId: 'inline-shell-item', range: { end: 7, start: 7 } }}
				thread={thread}
			/>
			<div data-testid="following-diff-row">Following diff row</div>
			<button data-testid="following-focus-target" type="button">
				Following focus target
			</button>
		</div>
	);
}

async function renderInlineShell(
	surface: RecordingAnnotationBrowserSurface,
): Promise<Awaited<ReturnType<typeof render>>> {
	return await render(
		<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
			<InlineShellProjection />
		</WorktreeAnnotationSurfaceProvider>,
	);
}

async function publishTwoMessageThread(surface: RecordingAnnotationBrowserSurface): Promise<void> {
	await act(async (): Promise<void> => {
		surface.publishProjectionState({
			expectedThreadCount: 1,
			revision: 3,
			sessions: [annotationSessionSummary({ revision: 3, sessionId: annotationSessionId })],
		});
		surface.publishThreadMessages({
			context: locatedContext,
			messages: [
				makeSavedMessage({ body: 'Root message.', messageId: rootMessageId }),
				makeSavedMessage({ body: 'Latest message.', messageId: latestMessageId, ordinal: 1 }),
			],
		});
		await Promise.resolve();
	});
}

function makeSavedMessage(props: {
	readonly body: string;
	readonly messageId: string;
	readonly ordinal?: number;
}): WorktreeAnnotationMessageEntry {
	return {
		...annotationMessage({
			messageId: props.messageId,
			...(props.ordinal === undefined ? {} : { ordinal: props.ordinal }),
			sessionRevision: 3,
			threadId,
		}),
		createdAt: Date.now() / 1000 - 978_307_200 - (props.ordinal ?? 0) * 60,
		savedBody: props.body,
	};
}

const threadId = '00000000-0000-7000-8000-000000000191';
const rootMessageId = '00000000-0000-7000-8000-000000000192';
const latestMessageId = '00000000-0000-7000-8000-000000000193';

const locatedContext: WorktreeAnnotationThreadContext = {
	diffSide: null,
	endLine: 7,
	path: 'Sources/App/View.swift',
	placement: 'exact',
	resolution: 'open',
	scope: 'located',
	sourceIdentity: 'descriptor-inline-shell',
	sourceRole: 'file',
	startLine: 7,
	threadId,
};

async function settleBrowserCondition(
	predicate: () => boolean,
	failureMessage: string,
	remainingFrames: number = 10,
): Promise<void> {
	await act(async (): Promise<void> => {
		await new Promise<void>((resolve): void => {
			requestAnimationFrame((): void => resolve());
		});
	});
	if (predicate()) return;
	if (remainingFrames <= 0) throw new Error(failureMessage);
	await settleBrowserCondition(predicate, failureMessage, remainingFrames - 1);
}
