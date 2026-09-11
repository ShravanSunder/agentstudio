import { act, type ReactElement } from 'react';
import { afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';
import { page, userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Test production rendering and scroll geometry.
import '../app/bridge-app.css';
import {
	BridgeViewerContextPanelProvider,
	BridgeViewerContextPanelViewport,
} from '../app/bridge-viewer-context-panel-host.js';
import { markdownCanvas } from '../app/markdown/bridge-markdown-annotation-test-support.js';
import { useWorktreeAnnotationNavigationTarget } from './use-worktree-annotation-navigation-target.js';
import {
	annotationSessionId,
	annotationHeadThreadId,
	annotationBaseThreadId,
	createWorktreeAnnotationBrowserProviderHarness,
} from './worktree-annotation-browser-test-support.js';
import {
	WorktreeAnnotationNavigationProvider,
	worktreeAnnotationDestination,
	type WorktreeAnnotationNavigationController,
} from './worktree-annotation-navigation.js';
import { WorktreeAnnotationShareHeaderControl } from './worktree-annotation-output-controls.js';
import { WorktreeAnnotationSharePreview } from './worktree-annotation-share-preview.js';
import { deriveWorktreeAnnotationShareProjection } from './worktree-annotation-share-projection.js';
import type { WorktreeAnnotationThreadProjection } from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationEditSurfaceToken,
	useWorktreeAnnotationEditorInstallationPreparation,
} from './worktree-annotation-surface-provider.js';

describe('annotation destination navigation', () => {
	beforeEach((): void => {
		const requestFrame = window.requestAnimationFrame.bind(window);
		vi.spyOn(window, 'requestAnimationFrame').mockImplementation((callback): number =>
			requestFrame((timestamp): void => {
				act((): void => callback(timestamp));
			}),
		);
	});
	afterEach((): void => {
		vi.restoreAllMocks();
	});
	test('makes the thread card keyboard accessible while preserving selected comment text', async () => {
		const thread = threadFixture(8);
		const open =
			vi.fn<(thread: WorktreeAnnotationThreadProjection, destination: 'file' | 'review') => void>();
		const screen = await render(
			<div style={{ width: 320 }}>
				<WorktreeAnnotationSharePreview
					scope="all"
					inlineThreads={
						deriveWorktreeAnnotationShareProjection({ scope: 'all', threads: [thread] })
							.inlineThreads
					}
					otherThreads={[]}
					readiness="current"
					activeSurface="file"
					onOpenThread={open}
				/>
			</div>,
		);
		const card = screen.getByRole('button', { name: /^Open:/ }).element();
		const title = card.querySelector('[data-slot="card-title"]');
		const range = card.querySelector('[data-thread-range]');
		const body = card.querySelector('p');
		if (title === null || range === null || body === null)
			throw new Error('Missing thread card content');
		expect(card.querySelector('button')).toBeNull();
		expect(range.getBoundingClientRect().top).toBeGreaterThan(title.getBoundingClientRect().top);
		expect(card.querySelector('[data-slot="separator"]')).toBeNull();
		const selection = document.getSelection();
		const selectedRange = document.createRange();
		selectedRange.selectNodeContents(body);
		selection?.removeAllRanges();
		selection?.addRange(selectedRange);
		act((): void => {
			body.dispatchEvent(new MouseEvent('click', { bubbles: true, detail: 1 }));
		});
		expect(open).not.toHaveBeenCalled();
		expect(selection?.toString()).toBe(body.textContent);
		selection?.removeAllRanges();
		await screen.getByRole('button', { name: /^Open:/ }).click();
		expect(open).toHaveBeenCalledExactlyOnceWith(
			expect.objectContaining({ context: thread.context }),
			'file',
		);
		open.mockClear();
		if (!(card instanceof HTMLElement)) throw new Error('Missing interactive card');
		card.focus();
		await userEvent.keyboard('{Enter}');
		expect(open).toHaveBeenCalledExactlyOnceWith(
			expect.objectContaining({ context: thread.context }),
			'file',
		);
		open.mockClear();
		await userEvent.keyboard(' ');
		expect(open).toHaveBeenCalledExactlyOnceWith(
			expect.objectContaining({ context: thread.context }),
			'file',
		);
	});

	test('offers current and alternate viewer actions without treating an old Review range as a current file range', async () => {
		const current = threadFixture(8);
		const oldReview = {
			...threadFixture(42),
			context: {
				...threadFixture(42).context,
				threadId: annotationBaseThreadId,
				sourceRole: 'review_base',
				placement: 'outdated',
			},
		} satisfies WorktreeAnnotationThreadProjection;
		const open =
			vi.fn<(thread: WorktreeAnnotationThreadProjection, destination: 'file' | 'review') => void>();
		const screen = await render(
			<WorktreeAnnotationSharePreview
				scope="all"
				inlineThreads={
					deriveWorktreeAnnotationShareProjection({ scope: 'all', threads: [current] })
						.inlineThreads
				}
				otherThreads={
					deriveWorktreeAnnotationShareProjection({ scope: 'all', threads: [oldReview] })
						.otherThreads
				}
				readiness="current"
				activeSurface="file"
				onOpenThread={open}
			/>,
		);
		const preview = screen.getByRole('region', { name: 'Annotation list' }).element();
		expect(preview.querySelectorAll('[data-slot="card"]')).toHaveLength(2);
		expect(preview.querySelectorAll('[data-thread-id]')).toHaveLength(2);
		expect(preview.querySelectorAll('button')).toHaveLength(0);
		expect(preview.querySelectorAll('[role="button"]')).toHaveLength(2);
		await screen.getByRole('button', { name: /^Open:/ }).click();
		expect(open).toHaveBeenLastCalledWith(
			expect.objectContaining({ context: current.context }),
			'file',
		);
		await screen.getByRole('button', { name: /^Open in Review:/ }).click();
		expect(open).toHaveBeenLastCalledWith(
			expect.objectContaining({ context: oldReview.context }),
			'review',
		);
		expect(
			worktreeAnnotationDestination(
				{ ...oldReview, context: { ...oldReview.context, sourceRole: 'file' } },
				'file',
			),
		).toBeNull();
		expect(
			worktreeAnnotationDestination(
				{ ...oldReview, context: { ...oldReview.context, placement: 'exact' } },
				'file',
			),
		).toBe('review');
	});

	test('failed destination draft preparation keeps the editor and never admits the jump', async () => {
		const harness = createWorktreeAnnotationBrowserProviderHarness('fileView');
		const finish = vi.fn<WorktreeAnnotationNavigationController['finish']>();
		const admit = vi.fn<WorktreeAnnotationNavigationController['admit']>();
		const controller = {
			activeSurface: 'file',
			request: {
				requestId: 9,
				phase: 'preparing',
				destination: 'file',
				sessionId: annotationSessionId,
				threadId: annotationHeadThreadId,
			},
			open: vi.fn(),
			finish,
			admit,
		} satisfies WorktreeAnnotationNavigationController;
		function Destination(): ReactElement {
			useWorktreeAnnotationEditSurfaceToken('existing-draft');
			useWorktreeAnnotationEditorInstallationPreparation(
				'existing-draft',
				async (): Promise<boolean> => false,
			);
			const resolved = useWorktreeAnnotationNavigationTarget('file', true);
			return (
				<>
					<textarea aria-label="Existing draft" defaultValue="Keep my draft" />
					<output>{resolved === null ? 'waiting' : 'admitted'}</output>
				</>
			);
		}
		const screen = await render(
			<WorktreeAnnotationNavigationProvider controller={controller}>
				{harness.wrap(<Destination />)}
			</WorktreeAnnotationNavigationProvider>,
		);
		await expect.poll(() => finish.mock.calls.length).toBeGreaterThan(0);
		expect(admit).not.toHaveBeenCalled();
		await expect
			.element(screen.getByRole('textbox', { name: 'Existing draft' }))
			.toHaveValue('Keep my draft');
		await expect.element(screen.getByText('waiting', { exact: true })).toBeVisible();
	});

	test('allows reopening the drawer while the same navigation request is pending', async () => {
		const harness = createWorktreeAnnotationBrowserProviderHarness('review');
		const controller = {
			activeSurface: 'review',
			request: {
				requestId: 1,
				phase: 'ready',
				destination: 'review',
				sessionId: annotationSessionId,
				threadId: annotationHeadThreadId,
			},
			open: vi.fn(),
			finish: vi.fn(),
			admit: vi.fn(),
		} satisfies WorktreeAnnotationNavigationController;
		const rendered = await render(
			<WorktreeAnnotationNavigationProvider controller={controller}>
				{harness.wrap(
					<BridgeViewerContextPanelProvider>
						<div className="h-[500px] w-[600px]">
							<WorktreeAnnotationShareHeaderControl />
							<BridgeViewerContextPanelViewport testId="navigation-drawer-viewport">
								<div>Code canvas</div>
							</BridgeViewerContextPanelViewport>
						</div>
					</BridgeViewerContextPanelProvider>,
				)}
			</WorktreeAnnotationNavigationProvider>,
		);
		await act(async (): Promise<void> => {
			await rendered.getByRole('button', { name: 'Annotations', exact: true }).click();
		});
		await expect.element(rendered.getByRole('button', { name: 'Close Annotations' })).toBeVisible();
	});

	test('waits for the destination session catalog before acquiring annotation content', async () => {
		const harness = createWorktreeAnnotationBrowserProviderHarness('review');
		const controller = {
			activeSurface: 'review',
			request: {
				requestId: 20,
				phase: 'preparing',
				destination: 'review',
				sessionId: annotationSessionId,
				threadId: annotationHeadThreadId,
			},
			open: vi.fn(),
			finish: vi.fn(),
			admit: vi.fn(),
		} satisfies WorktreeAnnotationNavigationController;
		function Destination(): ReactElement {
			useWorktreeAnnotationNavigationTarget('review', true);
			return <output>Destination</output>;
		}
		await render(
			<WorktreeAnnotationNavigationProvider controller={controller}>
				{harness.wrap(<Destination />)}
			</WorktreeAnnotationNavigationProvider>,
		);
		expect(
			harness.surface.sentOperations.filter((operation) => operation.kind === 'demand.acquire'),
		).toHaveLength(0);
		await act(async (): Promise<void> => {
			harness.surface.publishProjection(1, 0);
		});
		await expect
			.poll(
				() =>
					harness.surface.sentOperations.filter((operation) => operation.kind === 'demand.acquire')
						.length,
			)
			.toBe(1);
	});

	test('a missing destination session reports unavailability instead of waiting forever', async () => {
		const harness = createWorktreeAnnotationBrowserProviderHarness('fileView');
		const finish = vi.fn<WorktreeAnnotationNavigationController['finish']>();
		const controller = {
			activeSurface: 'file',
			request: {
				requestId: 10,
				phase: 'ready',
				destination: 'file',
				sessionId: '00000000-0000-7000-8000-000000000199',
				threadId: annotationHeadThreadId,
			},
			open: vi.fn(),
			finish,
			admit: vi.fn(),
		} satisfies WorktreeAnnotationNavigationController;
		function Destination(): ReactElement {
			const resolved = useWorktreeAnnotationNavigationTarget('file', true);
			return <output>{resolved === null ? 'waiting' : 'admitted'}</output>;
		}
		await render(
			<WorktreeAnnotationNavigationProvider controller={controller}>
				{harness.wrap(<Destination />)}
			</WorktreeAnnotationNavigationProvider>,
		);
		await act(async (): Promise<void> => {
			harness.surface.publishProjection(1, 0);
		});
		await expect.poll(() => finish.mock.calls.length).toBeGreaterThan(0);
		expect(finish).toHaveBeenCalledWith(10, 'This comment cannot be located in Files.');
	});

	test('waits for the destination Markdown thread, expands it and scrolls to its real host', async () => {
		const markdown =
			'# Start\n\n' + 'Paragraph before the annotation.\n\n'.repeat(60) + 'Target paragraph';
		const targetLine = markdown.split('\n').length;
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
		const screen = await render(
			<WorktreeAnnotationNavigationProvider controller={controller}>
				{harness.wrap(
					<div style={{ height: 280, width: 900 }}>{await markdownCanvas(markdown)}</div>,
				)}
			</WorktreeAnnotationNavigationProvider>,
		);
		await expect.element(screen.getByText('Target paragraph', { exact: true })).toBeInTheDocument();
		expect(finish).not.toHaveBeenCalled();
		const thread = threadFixture(targetLine);
		await act(async (): Promise<void> => {
			harness.surface.publishProjection(1, 1);
			harness.surface.publishThreadMessages(thread);
		});
		await expect.poll(() => finish.mock.calls.length).toBeGreaterThan(0);
		expect(finish).toHaveBeenCalledWith(1);
		const frame = screen.getByTestId('worktree-annotation-thread').element();
		expect(frame.getAttribute('data-annotation-expanded')).toBe('true');
		const owner = frame.closest('.bridge-scrollbar');
		if (!(owner instanceof HTMLElement)) throw new Error('Missing Markdown scroll owner');
		expect(owner.scrollTop).toBeGreaterThan(0);
		expect(frame.getBoundingClientRect().top).toBeGreaterThanOrEqual(
			owner.getBoundingClientRect().top,
		);
		expect(frame.getBoundingClientRect().bottom).toBeLessThanOrEqual(
			owner.getBoundingClientRect().bottom + 1,
		);
		await page.screenshot({
			element: owner,
			path: '../../../tmp/annotation-navigation-markdown.png',
		});
	});
});

function threadFixture(line: number): WorktreeAnnotationThreadProjection {
	return {
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
				attentionState: 'not_applicable',
				authorKind: 'human',
				createdAt: 1,
				draft: null,
				handled: false,
				messageId: '00000000-0000-7000-8000-000000000099',
				messageRevision: 1,
				ordinal: 0,
				savedBody: 'Navigate to this comment',
				savedRevision: 1,
				sessionId: annotationSessionId,
				sessionRevision: 1,
				status: 'locked',
				threadId: annotationHeadThreadId,
				threadRevision: 1,
			},
		],
	};
}
