import { act } from 'react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

import {
	annotationHeadThreadId,
	annotationMessage,
	createWorktreeAnnotationBrowserProviderHarness,
} from '../../worktree-annotations/worktree-annotation-browser-test-support.js';
import type { WorktreeAnnotationThreadProjection } from '../../worktree-annotations/worktree-annotation-surface-client.js';
import { markdownCanvas } from './bridge-markdown-annotation-test-support.js';

// oxlint-disable-next-line import/no-unassigned-import -- Exercise the real renderer and host geometry.
import '../bridge-app.css';

beforeEach((): void => {
	const requestFrame = window.requestAnimationFrame.bind(window);
	vi.spyOn(window, 'requestAnimationFrame').mockImplementation((callback): number =>
		requestFrame((timestamp): void => {
			act((): void => callback(timestamp));
		}),
	);
});

afterEach(async (): Promise<void> => {
	await act(async (): Promise<void> => {
		await cleanup();
	});
	vi.restoreAllMocks();
});

test('retires a pending range through a programmatic file round trip', async (): Promise<void> => {
	const harness = createWorktreeAnnotationBrowserProviderHarness('fileView');
	const screen = await render(harness.wrap(await markdownCanvas('First target\n\nSecond target')));
	await expect
		.element(screen.getByRole('button', { name: 'Select source lines 3–3' }))
		.toBeVisible();
	act((): void => {
		screen
			.getByRole('button', { name: 'Select source lines 3–3' })
			.element()
			.dispatchEvent(new MouseEvent('click', { bubbles: true }));
	});
	await expect.element(screen.getByTestId('bridge-markdown-source-selection')).toBeInTheDocument();
	// The provider survives the file loading gap; no outside-pointer dismissal occurs.
	await screen.rerender(harness.wrap(null));
	await screen.rerender(harness.wrap(await markdownCanvas('Other document', 1, 'other.md')));
	await expect.element(screen.getByText('Other document', { exact: true })).toBeVisible();
	await screen.rerender(harness.wrap(null));
	await screen.rerender(harness.wrap(await markdownCanvas('First target\n\nSecond target')));
	await expect
		.element(screen.getByRole('button', { name: 'Select source lines 3–3' }))
		.toBeVisible();
	await expect
		.element(screen.getByTestId('bridge-markdown-source-selection'))
		.not.toBeInTheDocument();
});

test('keeps saved thread coordinates with the painted document while another editor retains it', async (): Promise<void> => {
	const harness = createWorktreeAnnotationBrowserProviderHarness('fileView');
	const screen = await render(
		harness.wrap(await markdownCanvas('First target\n\nCommented target\n\nLast target')),
	);
	const thread = savedThread(1, 3);
	await act(async (): Promise<void> => {
		harness.surface.publishProjection(1, 1);
		harness.surface.publishThreadMessages(thread);
	});
	await expect.element(screen.getByText('Saved second target', { exact: true })).toBeVisible();
	await act(async (): Promise<void> => {
		await screen.getByRole('button', { name: 'Annotate source lines 1–1' }).click();
	});
	const editor = screen.getByPlaceholder('Write an annotation in Markdown').element();
	await screen.rerender(
		harness.wrap(
			await markdownCanvas('New target\n\nFirst target\n\nCommented target\n\nLast target', 2),
		),
	);
	await act(async (): Promise<void> => {
		harness.surface.publishProjection(2, 1);
		harness.surface.publishThreadMessages(savedThread(2, 5));
	});
	expect(screen.getByPlaceholder('Write an annotation in Markdown').element()).toBe(editor);
	const precedingTarget = (): string | null | undefined =>
		screen
			.getByText('Saved second target', { exact: true })
			.element()
			.closest('.bridge-markdown-annotation-host')?.previousElementSibling?.textContent;
	expect(precedingTarget()).toBe('Commented target');
	await act(async (): Promise<void> => {
		await screen.getByRole('button', { name: 'Revert annotation draft' }).click();
	});
	await expect.element(screen.getByText('New target', { exact: true })).toBeVisible();
	await expect.poll(precedingTarget).toBe('Commented target');
});

function savedThread(version: number, line: number): WorktreeAnnotationThreadProjection {
	return {
		context: {
			scope: 'located',
			path: 'plan.md',
			sourceIdentity: `plan-descriptor-${version}`,
			sourceRole: 'file',
			diffSide: null,
			placement: version === 1 ? 'exact' : 'relocated',
			resolution: 'open',
			startLine: line,
			endLine: line,
			threadId: annotationHeadThreadId,
		},
		messages: [
			{
				...annotationMessage({
					messageId: '00000000-0000-7000-8000-000000000091',
					threadId: annotationHeadThreadId,
				}),
				savedBody: 'Saved second target',
			},
		],
	};
}
