import { act, type ReactElement } from 'react';
import { afterEach, beforeEach, expect, test, vi } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

import { markdownCanvas } from '../app/markdown/bridge-markdown-annotation-test-support.js';
import {
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	createWorktreeAnnotationBrowserProviderHarness,
} from './worktree-annotation-browser-test-support.js';
import {
	WorktreeAnnotationNavigationProvider,
	type WorktreeAnnotationNavigationController,
} from './worktree-annotation-navigation.js';
import { WorktreeAnnotationSharePreview } from './worktree-annotation-share-preview.js';
import { deriveWorktreeAnnotationShareProjection } from './worktree-annotation-share-projection.js';
import { useWorktreeAnnotationProjection } from './worktree-annotation-surface-provider.js';

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

test.each([
	{ kind: 'fence delimiter', markdown: '```ts\nconst value = 1;\n```', line: 1 },
	{ kind: 'blank separator', markdown: 'First paragraph\n\nLast paragraph', line: 2 },
	{ kind: 'table delimiter', markdown: '| Name |\n| --- |\n| Value |', line: 2 },
])(
	'finishes navigation for a $kind while keeping its comment in Annotations',
	async ({ markdown, line }): Promise<void> => {
		const harness = createWorktreeAnnotationBrowserProviderHarness('fileView');
		const finish = vi.fn<WorktreeAnnotationNavigationController['finish']>();
		const controller = {
			activeSurface: 'file',
			request: {
				requestId: 1,
				phase: 'ready',
				destination: 'file',
				sessionId: annotationSessionId,
				threadId: annotationHeadThreadId,
			},
			open: vi.fn(),
			admit: vi.fn(),
			finish,
		} satisfies WorktreeAnnotationNavigationController;
		const wrap = (canvas: ReactElement | null): ReactElement => (
			<WorktreeAnnotationNavigationProvider controller={controller}>
				{harness.wrap(
					<>
						{canvas}
						<SavedAnnotations />
					</>,
				)}
			</WorktreeAnnotationNavigationProvider>
		);
		const screen = await render(wrap(await markdownCanvas('Another file', 1, 'other.md')));
		expect(finish).not.toHaveBeenCalled();
		await act(async (): Promise<void> => {
			harness.surface.publishProjection(1, 1);
			harness.surface.publishThreadMessages({
				context: {
					scope: 'located',
					path: 'plan.md',
					sourceIdentity: 'plan-descriptor-1',
					sourceRole: 'file',
					diffSide: null,
					placement: 'exact',
					resolution: 'open',
					startLine: line,
					endLine: line,
					threadId: annotationHeadThreadId,
				},
				messages: [
					{
						...annotationMessage({
							messageId: '00000000-0000-7000-8000-000000000095',
							threadId: annotationHeadThreadId,
						}),
						savedBody: 'Saved comment on Markdown source lines',
					},
				],
			});
		});
		// A ready request must not be rejected while the previous file is still displayed.
		expect(finish).not.toHaveBeenCalled();
		await screen.rerender(wrap(null));
		await screen.rerender(wrap(await markdownCanvas(markdown)));
		await expect
			.poll(() => finish.mock.calls)
			.toContainEqual([
				1,
				"This comment is attached to Markdown lines that aren't rendered. You can still read it in Annotations.",
			]);
		await expect
			.element(screen.getByText('Saved comment on Markdown source lines', { exact: true }))
			.toBeVisible();
		expect(screen.getByTestId('worktree-annotation-thread').query()).toBeNull();
		expect(
			harness.surface.sentOperations.some((operation): boolean => operation.kind === 'root.create'),
		).toBe(false);
	},
);

function SavedAnnotations(): ReactElement {
	const projection = useWorktreeAnnotationProjection();
	const shared = deriveWorktreeAnnotationShareProjection({
		scope: 'all',
		threads: projection.threads,
	});
	return (
		<WorktreeAnnotationSharePreview
			scope="all"
			inlineThreads={shared.inlineThreads}
			otherThreads={shared.otherThreads}
			readiness="current"
		/>
	);
}
