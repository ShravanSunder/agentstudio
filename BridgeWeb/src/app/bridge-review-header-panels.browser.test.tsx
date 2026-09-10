import { act, useState, type ReactElement } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';
import { page, userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production CSS.
import './bridge-app.css';
import {
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	annotationSecondSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from '../worktree-annotations/worktree-annotation-browser-test-support.js';
import { WorktreeAnnotationSurfaceProvider } from '../worktree-annotations/worktree-annotation-surface-provider.js';
import {
	BridgeReviewComparisonControl,
	type BridgeReviewComparisonControlProps,
} from './bridge-review-comparison-control.js';
import { BridgeReviewHeaderPanels } from './bridge-review-header-panels.js';
import {
	BridgeViewerContextPanelProvider,
	BridgeViewerContextPanelViewport,
} from './bridge-viewer-context-panel-host.js';

describe('Bridge Review header peer panels', () => {
	test('keeps Annotations openable and All selectable for a known empty catalog', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<PeerPanelsFixture surface={surface} />);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({ expectedThreadCount: 0, revision: 1, sessions: [] });
		});

		const annotationsTrigger = rendered.getByRole('button', {
			name: 'Annotations',
			exact: true,
		});
		await expect.element(annotationsTrigger).toBeEnabled();
		await performAction(() => annotationsTrigger.click());
		await expect.element(rendered.getByText('No pending comments.')).toBeVisible();
		await performAction(() => rendered.getByRole('button', { name: 'All comments, 0' }).click());
		await expect
			.element(rendered.getByRole('button', { name: 'All comments, 0' }))
			.toHaveAttribute('aria-pressed', 'true');
		await expect.element(rendered.getByText('No annotations yet.')).toBeVisible();
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeDisabled();
		await expect.element(rendered.getByRole('button', { name: 'Export JSON' })).toBeDisabled();
	});

	test('does not infer an all-sessions export when session selection is ambiguous', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<PeerPanelsFixture surface={surface} />);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 0,
				revision: 1,
				sessions: [
					annotationSessionSummary({ revision: 1, sessionId: annotationSessionId }),
					annotationSessionSummary({ revision: 1, sessionId: annotationSecondSessionId }),
				],
			});
		});

		const annotationsTrigger = rendered.getByRole('button', {
			name: 'Annotations',
			exact: true,
		});
		await expect.element(annotationsTrigger).toBeEnabled();
		await performAction(() => annotationsTrigger.click());
		await expect.element(rendered.getByText('Pending —')).toBeVisible();
		await performAction(() =>
			rendered.getByRole('button', { name: 'All comments, unknown' }).click(),
		);
		await expect
			.element(rendered.getByRole('button', { name: 'All comments, unknown' }))
			.toHaveAttribute('aria-pressed', 'true');
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeDisabled();
		await expect.element(rendered.getByRole('button', { name: 'Export JSON' })).toBeDisabled();
		expect(surface.sentOperations.filter(({ kind }) => kind === 'output.scope.commit')).toEqual([]);
	});

	test('keeps recovery-unavailable annotations openable while disabling output effects', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<PeerPanelsFixture surface={surface} />);
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 0,
				recoveryStatus: 'unavailable',
				revision: 1,
				sessions: [annotationSessionSummary({ revision: 1, sessionId: annotationSessionId })],
			});
		});

		const annotationsTrigger = rendered.getByRole('button', {
			name: 'Annotations',
			exact: true,
		});
		await expect.element(annotationsTrigger).toBeEnabled();
		await performAction(() => annotationsTrigger.click());
		await performAction(() => rendered.getByRole('button', { name: 'All comments, 0' }).click());
		await expect
			.element(rendered.getByRole('button', { name: 'All comments, 0' }))
			.toHaveAttribute('aria-pressed', 'true');
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeDisabled();
		await expect.element(rendered.getByRole('button', { name: 'Export JSON' })).toBeDisabled();
	});
	test('uses a plain drawer button and leaves the branch-search focus ring unclipped', async () => {
		const rendered = await render(
			<PeerPanelsFixture surface={new RecordingAnnotationBrowserSurface('review')} />,
		);
		const trigger = rendered.getByTestId('bridge-review-comparison-trigger').element();
		expect(trigger.querySelectorAll('svg')).toHaveLength(1);
		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
		const selector = rendered.getByTestId('bridge-review-comparison-branch-selector').element();
		expect(getComputedStyle(selector).overflow).toBe('visible');
		await expect.element(rendered.getByRole('combobox', { name: 'Search branches' })).toHaveFocus();
		await page.screenshot({ path: '../../../tmp/bridgeweb-compare-search-unclipped.png' });
	});
	test.each([500, 900])(
		'fills a %ipx drawer with branch results and anchors the cutoff note',
		async (height) => {
			const surface = new RecordingAnnotationBrowserSurface('review');
			const rendered = await render(
				<PeerPanelsFixture surface={surface} height={height} branchCount={80} />,
			);
			await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
			const panel = rendered.getByTestId('bridge-review-comparison-content').element();
			const scroll = rendered.getByTestId('bridge-review-comparison-branch-scroll').element();
			const note = rendered.getByTestId('bridge-review-comparison-catalog-explanation').element();
			const input = rendered.getByRole('combobox', { name: 'Search branches' }).element();
			const panelBounds = panel.getBoundingClientRect();
			const scrollBounds = scroll.getBoundingClientRect();
			const noteBounds = note.getBoundingClientRect();
			expect(noteBounds.bottom).toBeCloseTo(panelBounds.bottom - 18, 0);
			expect(scrollBounds.bottom).toBeCloseTo(noteBounds.top - 8, 0);
			expect(scrollBounds.top).toBeCloseTo(input.getBoundingClientRect().bottom + 8, 0);
			expect(scrollBounds.height).toBeGreaterThan(200);
			if (!(scroll instanceof HTMLElement)) throw new Error('Expected result scroll container.');
			expect(scroll.scrollHeight).toBeGreaterThan(scroll.clientHeight);
			// The virtualizer publishes both scroll start and a debounced scroll end.
			// Exercise both inside act without waiting on its wall-clock reset delay.
			vi.useFakeTimers({ toFake: ['setTimeout', 'clearTimeout'] });
			try {
				await act(async (): Promise<void> => {
					scroll.scrollTop = scroll.scrollHeight;
					scroll.dispatchEvent(new Event('scroll'));
					await vi.runOnlyPendingTimersAsync();
				});
			} finally {
				vi.useRealTimers();
			}
			await expect.element(rendered.getByTestId('comparison-branch-branch-79')).toBeVisible();
			expect(note.getBoundingClientRect().bottom).toBeCloseTo(noteBounds.bottom, 0);
			await page.screenshot({ path: '../../../tmp/bridgeweb-compare-filled-drawer.png' });
		},
	);
	test.each(['compare', 'share'] as const)(
		'makes exiting %s content inert before its animation finishes',
		async (outgoingKind) => {
			const surface = new RecordingAnnotationBrowserSurface('review');
			const applyTarget = vi.fn();
			const rendered = await render(
				<PeerPanelsFixture surface={surface} applyTarget={applyTarget} />,
			);
			await publishSavedComment(surface);
			const compareTrigger = rendered.getByTestId('bridge-review-comparison-trigger');
			const shareTrigger = rendered.getByRole('button', { name: 'Annotations', exact: true });
			await performAction(() =>
				(outgoingKind === 'compare' ? compareTrigger : shareTrigger).click(),
			);
			if (outgoingKind === 'compare') {
				await performAction(() =>
					rendered.getByRole('button', { name: 'Commit', exact: true }).click(),
				);
				await performAction(() =>
					rendered.getByRole('textbox', { name: 'Commit hash' }).fill('a'.repeat(40)),
				);
			}
			const outgoingPanel = rendered
				.getByTestId(
					outgoingKind === 'compare'
						? 'bridge-review-comparison-content'
						: 'worktree-annotation-share-shelf',
				)
				.element();
			const outgoingAction = rendered
				.getByRole('button', {
					name: outgoingKind === 'compare' ? 'Compare to this commit' : 'Copy Markdown',
				})
				.element();
			if (!(outgoingPanel instanceof HTMLElement) || !(outgoingAction instanceof HTMLElement))
				throw new Error('Expected mounted outgoing panel and action.');
			await act(async (): Promise<void> => {
				await (outgoingKind === 'compare' ? shareTrigger : compareTrigger).click();
			});
			const exitAnimations = outgoingPanel.getAnimations();
			for (const animation of exitAnimations) animation.pause();
			try {
				expect(outgoingPanel.isConnected).toBe(true);
				expect(outgoingPanel.inert).toBe(true);
				await act(async (): Promise<void> => {
					outgoingAction.focus();
					// Send a real pointer attempt without the driver's actionability wait;
					// browser hit-testing, not a synthetic DOM click, must reject the inert target.
					await userEvent.click(outgoingAction, { force: true });
				});
				expect(document.activeElement).not.toBe(outgoingAction);
				if (outgoingKind === 'compare') expect(applyTarget).not.toHaveBeenCalled();
				else
					expect(
						surface.sentOperations.filter((operation) => operation.kind === 'output.scope.commit'),
					).toHaveLength(0);
			} finally {
				for (const animation of exitAnimations) animation.play();
				await settlePanels();
			}
		},
	);
	test('opens Compare as the full-height inset context drawer', async () => {
		const rendered = await render(<ComparisonDrawerFixture />);
		const viewport = rendered.getByTestId('comparison-drawer-viewport').element();

		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());

		const panel = rendered.getByTestId('bridge-review-comparison-content').element();
		if (!(panel instanceof HTMLElement)) throw new Error('Expected Compare drawer element.');
		await waitForDrawerOpeningMotion(panel);
		const viewportBounds = viewport.getBoundingClientRect();
		const panelBounds = panel.getBoundingClientRect();
		expect(panel.getAttribute('data-slot')).toBe('drawer-popup');
		expect(panelBounds.top).toBeCloseTo(viewportBounds.top + 8, 0);
		expect(panelBounds.bottom).toBeCloseTo(viewportBounds.bottom - 8, 0);
		expect(viewportBounds.right - panelBounds.right).toBeCloseTo(8, 0);
		expect(panelBounds.width).toBeCloseTo(384, 0);
		await page.screenshot({ path: '../../../tmp/bridgeweb-compare-peer-drawer.png' });
	});

	test('switches peer panels while querying and cancelling Compare exactly once per session', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const queryTargets = vi.fn();
		const cancelTargetQuery = vi.fn();
		const rendered = await render(
			<PeerPanelsFixture
				cancelTargetQuery={cancelTargetQuery}
				queryTargets={queryTargets}
				surface={surface}
			/>,
		);

		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
		expect(queryTargets).toHaveBeenCalledTimes(1);

		await performAction(() =>
			rendered.getByRole('button', { name: 'Annotations', exact: true }).click(),
		);
		expect(cancelTargetQuery).toHaveBeenCalledTimes(1);
		await expect.element(rendered.getByRole('region', { name: 'Share comments' })).toBeVisible();
		expect(
			document.querySelectorAll('[data-slot="drawer-popup"]:not([data-ending-style])'),
		).toHaveLength(1);
		await expect
			.element(rendered.getByRole('button', { name: 'Pending comments, unknown' }))
			.toHaveFocus();

		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
		expect(queryTargets).toHaveBeenCalledTimes(2);
		await expect.element(rendered.getByTestId('bridge-review-comparison-content')).toBeVisible();
		expect(
			document.querySelectorAll('[data-slot="drawer-popup"]:not([data-ending-style])'),
		).toHaveLength(1);
		await expect.element(rendered.getByRole('combobox', { name: 'Search branches' })).toHaveFocus();
	});

	test('moves focus between comparison target modes and restores the enabled trigger on Escape', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<PeerPanelsFixture surface={surface} />);
		const trigger = rendered.getByTestId('bridge-review-comparison-trigger').element();

		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
		await expect.element(rendered.getByRole('combobox', { name: 'Search branches' })).toHaveFocus();
		await performAction(() =>
			rendered.getByRole('button', { name: 'Commit', exact: true }).click(),
		);
		await expect.element(rendered.getByRole('textbox', { name: 'Commit hash' })).toHaveFocus();
		await performAction(() =>
			rendered.getByRole('button', { name: 'Branch', exact: true }).click(),
		);
		await expect.element(rendered.getByRole('combobox', { name: 'Search branches' })).toHaveFocus();
		await performAction(() => userEvent.keyboard('{Escape}'));
		await expect.poll(() => document.activeElement).toBe(trigger);
	});

	test('focuses the labelled viewport itself when Apply disables the Compare trigger', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<PeerPanelsFixture surface={surface} />);
		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
		await performAction(() => rendered.getByTestId('comparison-branch-main').click());
		const viewport = rendered.getByTestId('comparison-peer-viewport').element();
		await expect.poll(() => document.activeElement).toBe(viewport);
		await expect.element(rendered.getByTestId('bridge-review-comparison-trigger')).toBeDisabled();
		expect(viewport.getAttribute('aria-label')).toBe('Viewer content');
		expect(viewport.getAttribute('tabindex')).toBe('-1');
	});

	test.each(['Copy Markdown', 'Export JSON', 'Repeat output attempt 1'])(
		'refuses Compare while %s owns the Share output lease',
		async (actionName) => {
			const surface = new RecordingAnnotationBrowserSurface('review');
			const queryTargets = vi.fn();
			const cancelTargetQuery = vi.fn();
			const rendered = await render(
				<PeerPanelsFixture
					surface={surface}
					queryTargets={queryTargets}
					cancelTargetQuery={cancelTargetQuery}
				/>,
			);
			const repeatsHistory = actionName === 'Repeat output attempt 1';
			await publishSavedComment(surface, repeatsHistory);
			await performAction(() =>
				rendered.getByRole('button', { name: 'Annotations', exact: true }).click(),
			);
			if (repeatsHistory) {
				await performAction(() => rendered.getByRole('button', { name: 'History (1)' }).click());
			}
			await performAction(() => rendered.getByRole('button', { name: actionName }).click());
			expect(
				surface.sentOperations.filter(
					(operation) =>
						operation.kind === (repeatsHistory ? 'output.repeat' : 'output.scope.commit'),
				),
			).toHaveLength(1);
			await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
			await expect.element(rendered.getByRole('region', { name: 'Share comments' })).toBeVisible();
			expect(rendered.getByTestId('bridge-review-comparison-content').query()).toBeNull();
			expect(queryTargets).not.toHaveBeenCalled();
			expect(cancelTargetQuery).not.toHaveBeenCalled();
			await performAction(() => surface.settleMostRecentOutput({ kind: 'destination_cancelled' }));
			await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
			await expect.element(rendered.getByTestId('bridge-review-comparison-content')).toBeVisible();
			expect(queryTargets).toHaveBeenCalledTimes(1);
		},
	);

	test('preserves the pending Share lease across Review deactivation and reactivation', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const queryTargets = vi.fn();
		const fixture = (isActive: boolean): ReactElement => (
			<PeerPanelsFixture surface={surface} isActive={isActive} queryTargets={queryTargets} />
		);
		const rendered = await render(fixture(true));
		await publishSavedComment(surface);
		await performAction(() =>
			rendered.getByRole('button', { name: 'Annotations', exact: true }).click(),
		);
		await performAction(() => rendered.getByRole('button', { name: 'Copy Markdown' }).click());
		await rendered.rerender(fixture(false));
		await settlePanels();
		await expect
			.element(rendered.getByRole('button', { name: 'Close Share comments' }))
			.toBeDisabled();
		await rendered.rerender(fixture(true));
		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
		expect(queryTargets).not.toHaveBeenCalled();
		await expect.element(rendered.getByRole('region', { name: 'Share comments' })).toBeVisible();
		await performAction(() => surface.settleMostRecentOutput({ kind: 'destination_cancelled' }));
		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
		expect(queryTargets).toHaveBeenCalledTimes(1);
	});

	test('cancels on deactivation and restores ordinary focus after reactivation', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const queryTargets = vi.fn();
		const cancelTargetQuery = vi.fn();
		const fixture = (isActive: boolean): ReactElement => (
			<PeerPanelsFixture
				surface={surface}
				isActive={isActive}
				queryTargets={queryTargets}
				cancelTargetQuery={cancelTargetQuery}
			/>
		);
		const rendered = await render(fixture(true));
		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
		await rendered.rerender(fixture(false));
		await settlePanels();
		expect(cancelTargetQuery).toHaveBeenCalledTimes(1);
		expect(rendered.getByTestId('bridge-review-comparison-content').query()).toBeNull();
		await rendered.rerender(fixture(true));
		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
		expect(queryTargets).toHaveBeenCalledTimes(2);
		await performAction(() => userEvent.keyboard('{Escape}'));
		await expect.element(rendered.getByTestId('bridge-review-comparison-trigger')).toHaveFocus();
		expect(cancelTargetQuery).toHaveBeenCalledTimes(2);
	});

	test('keeps the open query across rerenders and returns focus to the viewport during refresh', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const queryTargets = vi.fn();
		const cancelTargetQuery = vi.fn();
		const fixture = (disabled: boolean): ReactElement => (
			<PeerPanelsFixture
				surface={surface}
				disabled={disabled}
				queryTargets={queryTargets}
				cancelTargetQuery={cancelTargetQuery}
			/>
		);
		const rendered = await render(fixture(false));
		await performAction(() => rendered.getByTestId('bridge-review-comparison-trigger').click());
		await rendered.rerender(fixture(true));
		await settlePanels();
		expect(queryTargets).toHaveBeenCalledTimes(1);
		expect(cancelTargetQuery).not.toHaveBeenCalled();
		await performAction(() => userEvent.keyboard('{Escape}'));
		await expect.element(rendered.getByTestId('comparison-peer-viewport')).toHaveFocus();
		expect(cancelTargetQuery).toHaveBeenCalledTimes(1);
	});
});

function ComparisonDrawerFixture(): ReactElement {
	const [open, setOpen] = useState(false);
	return (
		<BridgeViewerContextPanelProvider>
			<div className="grid h-[500px] w-[600px] grid-rows-[auto_minmax(0,1fr)]">
				<div>
					<BridgeReviewComparisonControl
						comparisonPresentation={null}
						displayedReviewPackage={null}
						finalFocus={({ trigger }): HTMLElement | null => trigger}
						onApplyTarget={vi.fn()}
						onOpenChange={(nextOpen): boolean => {
							setOpen(nextOpen);
							return true;
						}}
						open={open}
					/>
				</div>
				<BridgeViewerContextPanelViewport testId="comparison-drawer-viewport">
					<div>Code canvas</div>
				</BridgeViewerContextPanelViewport>
			</div>
		</BridgeViewerContextPanelProvider>
	);
}

function PeerPanelsFixture(props: {
	readonly height?: number;
	readonly branchCount?: number;
	readonly applyTarget?: BridgeReviewComparisonControlProps['onApplyTarget'];
	readonly cancelTargetQuery?: () => void;
	readonly queryTargets?: () => void;
	readonly surface: RecordingAnnotationBrowserSurface;
	readonly isActive?: boolean;
	readonly disabled?: boolean;
}): ReactElement {
	return (
		<WorktreeAnnotationSurfaceProvider surfaceClient={props.surface.client}>
			<BridgeViewerContextPanelProvider>
				<div
					className="grid w-[600px] grid-rows-[auto_minmax(0,1fr)]"
					style={{ height: props.height ?? 500 }}
				>
					<div>
						<BridgeReviewHeaderPanels
							comparisonPresentation={null}
							displayedReviewPackage={null}
							isActive={props.isActive ?? true}
							disabled={props.disabled ?? false}
							onApplyTarget={props.applyTarget ?? vi.fn()}
							onCancelTargetQuery={props.cancelTargetQuery ?? (() => {})}
							onQueryTargets={props.queryTargets ?? (() => {})}
							targetQueryState={{
								catalog: {
									branches: Array.from({ length: props.branchCount ?? 1 }, (_, index) => ({
										branchName: index === 0 ? 'main' : `branch-${index}`,
										kind: 'local' as const,
										oid: 'a'.repeat(40),
									})),
									capturedAtUnixMilliseconds: 1,
									currentTarget: null,
									cutoffUnixMilliseconds: 0,
									defaultTarget: null,
									isTruncated: false,
								},
								message: null,
								status: 'ready',
							}}
						/>
					</div>
					<BridgeViewerContextPanelViewport testId="comparison-peer-viewport">
						<button type="button">Focusable code descendant</button>
					</BridgeViewerContextPanelViewport>
				</div>
			</BridgeViewerContextPanelProvider>
		</WorktreeAnnotationSurfaceProvider>
	);
}

async function waitForDrawerOpeningMotion(drawer: HTMLElement): Promise<void> {
	await expect.poll(() => drawer.hasAttribute('data-starting-style')).toBe(false);
	await Promise.all(drawer.getAnimations().map((animation) => animation.finished));
}

async function performAction(action: () => Promise<void> | void): Promise<void> {
	await act(async (): Promise<void> => {
		await action();
	});
	await settlePanels();
}

async function settlePanels(): Promise<void> {
	for (let frame = 0; frame < 10; frame += 1) {
		await act(async (): Promise<void> => {
			await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
			const animations = [...document.querySelectorAll('[data-slot="drawer-popup"]')].flatMap(
				(panel) => panel.getAnimations(),
			);
			for (const animation of animations) animation.finish();
			await Promise.all(
				animations.map(async (animation) => {
					await animation.finished.catch(() => {});
				}),
			);
		});
		if (
			document.querySelector(
				'[data-slot="drawer-popup"][data-starting-style], [data-slot="drawer-popup"][data-ending-style]',
			) === null
		)
			return;
	}
	throw new Error('Drawer motion did not reach a settled state.');
}

async function publishSavedComment(
	surface: RecordingAnnotationBrowserSurface,
	includeHistory = false,
): Promise<void> {
	await performAction(() => {
		surface.publishProjectionState({
			...(includeHistory
				? {
						outputHistory: [
							{
								attemptId: '00000000-0000-7000-8000-000000000085',
								canMarkNotHandled: false,
								createdAt: 1,
								messageCount: 1,
								outputKind: 'clipboard_markdown' as const,
								repeatedFromAttemptId: null,
								sessionId: annotationSessionId,
								state: 'unknown' as const,
								updatedAt: 1,
							},
						],
					}
				: {}),
			expectedThreadCount: 1,
			revision: 3,
			sessions: [
				annotationSessionSummary({
					eligibleMessageCount: 1,
					revision: 3,
					sessionId: annotationSessionId,
				}),
			],
		});
		surface.publishThreadMessages({
			context: {
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
			},
			messages: [
				annotationMessage({
					messageId: '00000000-0000-7000-8000-000000000081',
					sessionRevision: 3,
					threadId: annotationHeadThreadId,
				}),
			],
		});
	});
}
