import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import { RecordingAnnotationBrowserSurface } from './worktree-annotation-browser-test-support.js';
import {
	useWorktreeAnnotationProjection,
	WorktreeAnnotationSurfaceProvider,
} from './worktree-annotation-surface-provider.js';
import {
	makeSavedMessage,
	publishThreadMessages,
	renderAnnotationProjection,
	rootMessageId,
	settleBrowserCondition,
} from './worktree-annotation-thread.browser.test-support.js';
import { WorktreeAnnotationThread } from './worktree-annotation-thread.js';

describe('worktree annotation inline thread exit', () => {
	test('leaves an active one-message thread on outside click or Escape', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderLocatedAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'One active message.', messageId: rootMessageId }),
		]);
		const thread = rendered.getByTestId('worktree-annotation-thread').element();
		const activeSurface = (): HTMLElement | null =>
			thread.querySelector('[data-worktree-annotation-interaction][data-annotation-active="true"]');

		await act(async (): Promise<void> => {
			thread.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
		});
		expect(activeSurface()).not.toBeNull();
		await act(async (): Promise<void> => {
			document.body.click();
			await Promise.resolve();
		});
		expect(activeSurface()).toBeNull();

		await act(async (): Promise<void> => {
			thread.dispatchEvent(new MouseEvent('click', { bubbles: true }));
			await Promise.resolve();
		});
		expect(activeSurface()).not.toBeNull();
		await act(async (): Promise<void> => {
			thread.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
			await Promise.resolve();
		});
		expect(activeSurface()).toBeNull();
	});

	test('flushes the active editor before outside press collapses the inline thread', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await renderAnnotationProjection(surface);
		await publishThreadMessages(surface, [
			makeSavedMessage({ body: 'Outside-close root.', messageId: rootMessageId }),
		]);
		const replyButton = rendered
			.getByTestId('worktree-annotation-thread')
			.getByRole('button', { name: 'Reply to annotation thread' });
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
