import { act, type ReactElement } from 'react';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';
import { page, userEvent } from 'vitest/browser';

const toastSpies = vi.hoisted(() => ({
	default: vi.fn<(message: string) => void>(),
	error: vi.fn<(message: string) => void>(),
	success: vi.fn<(message: string, options?: unknown) => void>(),
	warning: vi.fn<(message: string) => void>(),
}));
vi.mock('sonner', () => ({
	toast: Object.assign(toastSpies.default, {
		error: toastSpies.error,
		success: toastSpies.success,
		warning: toastSpies.warning,
	}),
}));

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import { BridgeViewerContentHeader } from '../app/bridge-viewer-content-header.js';
import type { BridgeProductWorktreeAnnotationOperation } from '../core/comm-worker/bridge-product-call-contracts.js';
import {
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import { WorktreeAnnotationShareHeaderControl } from './worktree-annotation-output-controls.js';
import type {
	WorktreeAnnotationMessageEntry,
	WorktreeAnnotationOutputHistorySummary,
	WorktreeAnnotationThreadContext,
} from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationProjection,
	useWorktreeAnnotationViewedController,
	WorktreeAnnotationSurfaceProvider,
} from './worktree-annotation-surface-provider.js';

const handledMessageId = '00000000-0000-7000-8000-000000000081';
const newMessageId = '00000000-0000-7000-8000-000000000082';
const unavailableMessageId = '00000000-0000-7000-8000-000000000083';
const unavailableThreadId = '00000000-0000-7000-8000-000000000084';
const successfulAttemptId = '00000000-0000-7000-8000-000000000085';

describe('worktree annotation Share comments integrated surface', () => {
	afterEach(async (): Promise<void> => {
		await act(async (): Promise<void> => {
			await cleanup();
			await Promise.resolve();
		});
		toastSpies.default.mockReset();
		toastSpies.error.mockReset();
		toastSpies.success.mockReset();
		toastSpies.warning.mockReset();
	});

	test('opens a centered 90%-width header shelf without moving the code canvas', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<ShareSurfaceFixture surface={surface} />);
		await publishShareProjection(surface);
		const header = rendered.getByTestId('bridge-viewer-content-topbar').element();
		const codeCanvas = rendered.getByTestId('share-layout-code-canvas').element();
		const codeCanvasTopBeforeOpen = codeCanvas.getBoundingClientRect().top;

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);

		const shelf = rendered.getByTestId('worktree-annotation-share-shelf').element();
		const headerBounds = header.getBoundingClientRect();
		const shelfBounds = shelf.getBoundingClientRect();
		expect(codeCanvas.getBoundingClientRect().top).toBe(codeCanvasTopBeforeOpen);
		expect(shelfBounds.width).toBeCloseTo(headerBounds.width * 0.9, 0);
		expect(shelfBounds.left - headerBounds.left).toBeCloseTo(headerBounds.width * 0.05, 0);
		expect(getComputedStyle(shelf).transitionDuration).toBe('0.12s');
		expect(shelf.getAttribute('data-side')).toBe('bottom');
		expect(shelf.className).toContain('motion-reduce:translate-y-0');
		expect(shelf.className).toContain('max-h-[var(--available-height)]');
		expect(document.querySelector('[data-slot="popover-content"]')).toBe(shelf);
	});

	test('dismisses the shelf on outside press without stealing outside focus', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<ShareSurfaceFixture surface={surface} />);
		await publishShareProjection(surface);
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		const outsideTarget = rendered.getByRole('button', { name: 'Code canvas target' });
		const closingShelf = requireHtmlElement(
			rendered.getByTestId('worktree-annotation-share-shelf').element(),
		);

		await act(async (): Promise<void> => {
			await outsideTarget.click();
			await finishShareShelfMotion(closingShelf);
		});

		await expect
			.element(rendered.getByRole('region', { name: 'Share comments' }))
			.not.toBeInTheDocument();
		expect(document.activeElement).toBe(outsideTarget.element());
	});

	test('presents unknown membership before the first complete projection', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<ShareSurfaceFixture surface={surface} />);

		await expect.element(rendered.getByRole('button', { name: 'Share comments' })).toBeEnabled();
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		await expect.element(rendered.getByRole('region', { name: 'Share comments' })).toBeVisible();
		await expect.element(rendered.getByText('Pending —')).toBeVisible();
		await expect.element(rendered.getByText('All —')).toBeVisible();
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeDisabled();
		await expect.element(rendered.getByRole('button', { name: 'Export JSON' })).toBeDisabled();
	});

	test('preserves All membership but disables output until viewed projection convergence', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<ShareSurfaceFixture includeViewedControl surface={surface} />);
		const agentMessage = {
			...annotationMessage({ messageId: newMessageId, threadId: annotationHeadThreadId }),
			attentionState: 'new' as const,
			authorKind: 'agent' as const,
			sessionRevision: 3,
		};
		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 1,
				revision: 3,
				sessions: [annotationSessionSummary({ revision: 3, sessionId: annotationSessionId })],
			});
			surface.publishThreadMessages({ context: locatedContext, messages: [agentMessage] });
			await settleInteraction();
		});
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'All comments, 1' }).click(),
		);
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeEnabled();

		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Mark agent viewed' }).click(),
		);
		await settleInteraction();
		await act(async (): Promise<void> => {
			surface.settleMostRecentViewed(5);
			await settleInteraction();
		});
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeDisabled();
		await expect.element(rendered.getByRole('button', { name: 'Export JSON' })).toBeDisabled();

		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 1,
				revision: 4,
				sessions: [annotationSessionSummary({ revision: 5, sessionId: annotationSessionId })],
			});
			surface.publishThreadMessages({
				context: locatedContext,
				messages: [{ ...agentMessage, attentionState: 'viewed', sessionRevision: 5 }],
			});
			await settleInteraction();
		});
		await expect.element(rendered.getByRole('button', { name: 'Copy Markdown' })).toBeEnabled();
	});

	test.each(['fileView', 'review'] as const)(
		'uses the %s header entry and exact All scope, then dismisses with reversible success',
		async (surfaceKind) => {
			const surface = new RecordingAnnotationBrowserSurface(surfaceKind);
			const rendered = await render(<ShareSurfaceFixture surface={surface} />);
			await publishShareProjection(surface);

			await expect.element(rendered.getByRole('button', { name: 'Share comments' })).toBeEnabled();
			await performBrowserAction(() => {
				clickHtmlButton(rendered.getByRole('button', { name: 'Share comments' }).element());
			});
			const pendingScopeButton = requireShareScopeButton('Pending comments');
			expect(pendingScopeButton.getAttribute('aria-label')).toBe('Pending comments, 2');
			expect(pendingScopeButton.getAttribute('aria-pressed')).toBe('true');
			expect(document.querySelector('[aria-label="Other saved comments"]')).toBeNull();
			if (surfaceKind === 'review') {
				const integratedSurface = rendered
					.getByTestId('review-or-file-header')
					.element().parentElement;
				if (integratedSurface === null)
					throw new Error('Expected the integrated Share surface root.');
				await page.screenshot({
					element: integratedSurface,
					path: '../../../tmp/bridgeweb-worktree-annotation-share-integrated.png',
				});
			}

			const allScopeButton = requireShareScopeButton('All comments');
			expect(allScopeButton.getAttribute('aria-label')).toBe('All comments, 3');
			await performBrowserAction(async (): Promise<void> => allScopeButton.click());
			await performBrowserAction(() => {
				clickHtmlButton(rendered.getByRole('button', { name: 'Copy Markdown' }).element());
			});
			expect(findLastOperation(surface, 'output.scope.commit')).toEqual({
				displayedProjectionRevision: 3,
				expectedSessionRevision: 3,
				kind: 'output.scope.commit',
				outputKind: 'clipboardMarkdown',
				scope: 'all',
				sessionId: annotationSessionId,
				sourceGeneration: 3,
			});

			const closingShelf = requireHtmlElement(
				rendered.getByTestId('worktree-annotation-share-shelf').element(),
			);
			await act(async (): Promise<void> => {
				surface.settleMostRecentOutput({
					kind: 'succeeded',
					summary: outputSummary('clipboard_markdown', 3),
				});
				await Promise.resolve();
			});
			await act(async (): Promise<void> => finishShareShelfMotion(closingShelf));
			await expect
				.element(rendered.getByRole('region', { name: 'Share comments' }))
				.not.toBeInTheDocument();
			expect(toastSpies.success).toHaveBeenCalledWith(
				'Copied 3 annotations',
				expect.objectContaining({
					action: expect.objectContaining({ label: 'Mark as not handled' }),
				}),
			);
			const toastAction = toastSpies.success.mock.calls.at(-1)?.[1];
			if (!isToastAction(toastAction))
				throw new Error('Expected a reversible success toast action.');
			await act(async (): Promise<void> => {
				toastAction.action.onClick();
				await settleInteraction();
			});
			expect(findLastOperation(surface, 'output.handled.clear')).toEqual({
				attemptId: successfulAttemptId,
				expectedSessionRevision: 4,
				kind: 'output.handled.clear',
			});
		},
	);

	test('keeps unavailable comments out of Share presentation while preserving All membership', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<ShareSurfaceFixture surface={surface} />);
		await publishShareProjection(surface);
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		await settleInteraction();

		expect(document.querySelector('[aria-label="Other saved comments"]')).toBeNull();
		expect(document.body.textContent).not.toContain('Unavailable saved comment');
		await expect.element(rendered.getByRole('button', { name: 'All comments, 3' })).toBeVisible();
	});

	test('keeps failure and cancellation in Share, but closes partial success with a warning toast', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<ShareSurfaceFixture surface={surface} />);
		await publishShareProjection(surface);
		await performBrowserAction(() => {
			clickHtmlButton(rendered.getByRole('button', { name: 'Share comments' }).element());
		});

		await performBrowserAction(() => {
			clickHtmlButton(rendered.getByRole('button', { name: 'Export JSON' }).element());
		});
		await act(async (): Promise<void> => {
			surface.settleMostRecentOutput({ kind: 'destination_cancelled' });
			await settleInteraction();
		});
		await expect.element(rendered.getByRole('region', { name: 'Share comments' })).toBeVisible();

		await performBrowserAction(() => {
			clickHtmlButton(rendered.getByRole('button', { name: 'Export JSON' }).element());
		});
		const closingShelf = requireHtmlElement(
			rendered.getByTestId('worktree-annotation-share-shelf').element(),
		);
		await act(async (): Promise<void> => {
			surface.settleMostRecentOutput({
				effectError: 'write failed',
				kind: 'effect_failed',
				summary: outputSummary('json_file'),
			});
			await Promise.resolve();
			await Promise.resolve();
		});
		await expect.element(rendered.getByRole('alert')).toHaveTextContent('Export failed.');

		await performBrowserAction(() => {
			clickHtmlButton(rendered.getByRole('button', { name: 'Copy Markdown' }).element());
		});
		await act(async (): Promise<void> => {
			surface.settleMostRecentOutput({
				finalizationError: 'history failed',
				kind: 'partial_success',
				summary: outputSummary('clipboard_markdown'),
			});
			await Promise.resolve();
		});
		await act(async (): Promise<void> => finishShareShelfMotion(closingShelf));
		await expect
			.element(rendered.getByRole('region', { name: 'Share comments' }))
			.not.toBeInTheDocument();
		expect(toastSpies.warning).toHaveBeenCalledWith(
			'Clipboard contains 2 annotations, but durable history was not recorded.',
		);
		expect(toastSpies.success).not.toHaveBeenCalled();
	});

	test('keeps durable history in the Share shelf and exposes unhandle only for an eligible success', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const rendered = await render(<ShareSurfaceFixture surface={surface} />);
		await publishShareProjection(surface, true);
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);

		await expect.element(rendered.getByRole('button', { name: 'History (1)' })).toBeVisible();
		expect(document.querySelector('[data-slot="popover-content"]')).not.toBeNull();
		await performBrowserAction(() => rendered.getByRole('button', { name: 'History (1)' }).click());
		await expect.element(rendered.getByText('Clipboard Markdown · 3 annotations')).toBeVisible();
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Mark as not handled' }).click(),
		);
		expect(findLastOperation(surface, 'output.handled.clear')).toEqual({
			attemptId: successfulAttemptId,
			expectedSessionRevision: 3,
			kind: 'output.handled.clear',
		});
	});

	test('locks shelf dismissal while History Repeat is unresolved', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<ShareSurfaceFixture surface={surface} />);
		await publishShareProjection(surface, 'unknown');
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		await performBrowserAction(() => rendered.getByRole('button', { name: 'History (1)' }).click());
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Repeat output attempt 1' }).click(),
		);

		await expect
			.element(rendered.getByRole('button', { name: 'Close Share comments' }))
			.toBeDisabled();
		await performBrowserAction(() => userEvent.keyboard('{Escape}'));
		await expect.element(rendered.getByRole('region', { name: 'Share comments' })).toBeVisible();
		expect(
			rendered
				.getByTestId('worktree-annotation-share-shelf')
				.element()
				.hasAttribute('data-ending-style'),
		).toBe(false);

		await act(async (): Promise<void> => {
			surface.settleMostRecentOutput({
				effectError: 'repeat failed',
				kind: 'effect_failed',
				summary: outputSummary('clipboard_markdown'),
			});
			await settleInteraction();
		});
		await expect.element(rendered.getByRole('region', { name: 'Share comments' })).toBeVisible();
	});

	test('uses one output lease across Share commands and History Repeat', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<ShareSurfaceFixture surface={surface} />);
		await publishShareProjection(surface, 'unknown');
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		await performBrowserAction(() => rendered.getByRole('button', { name: 'History (1)' }).click());
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Copy Markdown' }).click(),
		);

		await expect
			.element(rendered.getByRole('button', { name: 'Repeat output attempt 1' }))
			.toBeDisabled();
		await expect
			.element(rendered.getByRole('button', { name: 'Close Share comments' }))
			.toBeDisabled();
		expect(
			surface.sentOperations.filter((operation) => operation.kind === 'output.repeat'),
		).toHaveLength(0);
		await act(async (): Promise<void> => {
			surface.settleMostRecentOutput({ kind: 'destination_cancelled' });
			await settleInteraction();
		});
	});

	test.each(['fileView', 'review'] as const)(
		'keeps collapsed and expanded History outside the %s Share command hit area',
		async (surfaceKind) => {
			const surface = new RecordingAnnotationBrowserSurface(surfaceKind);
			const rendered = await render(
				<ShareSurfaceGridFixture surface={surface} surfaceKind={surfaceKind} />,
			);
			await publishShareProjection(surface, true);
			await performBrowserAction(() =>
				rendered.getByRole('button', { name: 'Share comments' }).click(),
			);

			const shareLayoutOwner = rendered.getByTestId('worktree-annotation-share-shelf').element();
			expect(
				shareLayoutOwner.contains(
					rendered.getByRole('button', { name: 'Copy Markdown' }).element(),
				),
			).toBe(true);
			expect(
				shareLayoutOwner.contains(rendered.getByRole('button', { name: 'History (1)' }).element()),
			).toBe(true);
			assertElementOwnsItsCenterHitTarget(
				rendered.getByRole('button', { name: 'Copy Markdown' }).element(),
			);
			await act(async (): Promise<void> => {
				await rendered.getByRole('button', { name: 'History (1)' }).click();
				await settleInteraction();
			});
			assertElementOwnsItsCenterHitTarget(
				rendered.getByRole('button', { name: 'Copy Markdown' }).element(),
			);
		},
	);

	test('retries unhandle once after the output projection advances past a revision conflict', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<ShareSurfaceFixture surface={surface} />);
		await publishShareProjection(surface, true);
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		await performBrowserAction(() => rendered.getByRole('button', { name: 'History (1)' }).click());
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Mark as not handled' }).click(),
		);

		await act(async (): Promise<void> => {
			surface.settleMostRecentConflict('output.handled.clear');
			await settleInteraction();
		});
		expect(outputHandledClearOperations(surface)).toEqual([
			{
				attemptId: successfulAttemptId,
				expectedSessionRevision: 3,
				kind: 'output.handled.clear',
			},
		]);

		await act(async (): Promise<void> => {
			surface.publishProjectionState({
				expectedThreadCount: 0,
				outputHistory: [successfulHistorySummary()],
				revision: 5,
				sessions: [
					annotationSessionSummary({
						eligibleMessageCount: 3,
						eligibleWithoutInlinePlacementCount: 1,
						revision: 4,
						sessionId: annotationSessionId,
					}),
				],
			});
			await settleInteraction();
		});
		await expect.poll(() => outputHandledClearOperations(surface).length).toBe(2);
		expect(outputHandledClearOperations(surface)[1]).toEqual({
			attemptId: successfulAttemptId,
			expectedSessionRevision: 4,
			kind: 'output.handled.clear',
		});
	});

	test('stops a conflicted unhandle when its review session disappears', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const rendered = await render(<ShareSurfaceFixture surface={surface} />);
		await publishShareProjection(surface, true);
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Share comments' }).click(),
		);
		await performBrowserAction(() => rendered.getByRole('button', { name: 'History (1)' }).click());
		await performBrowserAction(() =>
			rendered.getByRole('button', { name: 'Mark as not handled' }).click(),
		);

		await act(async (): Promise<void> => {
			surface.settleMostRecentConflict('output.handled.clear');
			await settleInteraction();
			surface.publishProjectionState({
				expectedThreadCount: 0,
				outputHistory: [],
				revision: 5,
				sessions: [],
			});
			await settleInteraction();
		});

		expect(toastSpies.error).toHaveBeenCalledWith('The review session is no longer available.');
		expect(outputHandledClearOperations(surface)).toHaveLength(1);
	});
});

function ShareSurfaceFixture(props: {
	readonly includeViewedControl?: boolean;
	readonly surface: RecordingAnnotationBrowserSurface;
}): ReactElement {
	return (
		<WorktreeAnnotationSurfaceProvider surfaceClient={props.surface.client}>
			{props.includeViewedControl === true ? <ViewedCommandTestControl /> : null}
			<div className="w-[600px]" data-testid="review-or-file-header">
				<BridgeViewerContentHeader
					controls={<WorktreeAnnotationShareHeaderControl />}
					mode="review"
					statusText={null}
					title="Sources/First.swift"
				/>
				<button className="mt-16" data-testid="share-layout-code-canvas" type="button">
					Code canvas target
				</button>
			</div>
		</WorktreeAnnotationSurfaceProvider>
	);
}

function ShareSurfaceGridFixture(props: {
	readonly surface: RecordingAnnotationBrowserSurface;
	readonly surfaceKind: 'fileView' | 'review';
}): ReactElement {
	return (
		<WorktreeAnnotationSurfaceProvider surfaceClient={props.surface.client}>
			<div className="w-[600px]" data-testid="share-surface-grid-fixture">
				<BridgeViewerContentHeader
					controls={<WorktreeAnnotationShareHeaderControl />}
					mode={props.surfaceKind === 'review' ? 'review' : 'file'}
					statusText={null}
					title="Sources/First.swift"
				/>
				{props.surfaceKind === 'review' ? <div>Comparison status</div> : null}
				<div data-testid="share-layout-code-canvas">Code canvas</div>
			</div>
		</WorktreeAnnotationSurfaceProvider>
	);
}

function assertElementOwnsItsCenterHitTarget(element: Element): void {
	const bounds = element.getBoundingClientRect();
	const hitTarget = document.elementFromPoint(
		bounds.left + bounds.width / 2,
		bounds.top + bounds.height / 2,
	);
	expect(element.contains(hitTarget)).toBe(true);
}

function ViewedCommandTestControl(): ReactElement {
	const projection = useWorktreeAnnotationProjection();
	const viewedController = useWorktreeAnnotationViewedController();
	return (
		<button
			type="button"
			onClick={() => {
				const messages = projection.threads.flatMap((thread) => thread.messages);
				void viewedController.markMessagesViewed(annotationSessionId, messages);
			}}
		>
			Mark agent viewed
		</button>
	);
}

async function publishShareProjection(
	surface: RecordingAnnotationBrowserSurface,
	includeHistory: boolean | 'unknown' = false,
): Promise<void> {
	await act(async (): Promise<void> => {
		surface.publishProjectionState({
			expectedThreadCount: 2,
			...(includeHistory !== false
				? {
						outputHistory: [
							includeHistory === 'unknown' ? unknownHistorySummary() : successfulHistorySummary(),
						],
					}
				: {}),
			revision: 3,
			sessions: [
				annotationSessionSummary({
					eligibleMessageCount: 3,
					eligibleWithoutInlinePlacementCount: 1,
					revision: 3,
					sessionId: annotationSessionId,
				}),
			],
		});
		surface.publishThreadMessages({
			context: locatedContext,
			messages: [
				savedMessage({ body: 'Handled saved comment', handled: true, messageId: handledMessageId }),
				savedMessage({
					body: 'New saved comment',
					handled: false,
					messageId: newMessageId,
					ordinal: 1,
				}),
			],
		});
		surface.publishThreadMessages({
			context: unavailableContext,
			messages: [
				savedMessage({
					body: '## Unavailable saved comment\n\n- Preserved list item',
					handled: false,
					messageId: unavailableMessageId,
					threadId: unavailableThreadId,
				}),
			],
		});
		await settleInteraction();
	});
}

function unknownHistorySummary(): WorktreeAnnotationOutputHistorySummary {
	return {
		...successfulHistorySummary(),
		canMarkNotHandled: false,
		state: 'unknown',
	};
}

function successfulHistorySummary(): WorktreeAnnotationOutputHistorySummary {
	return {
		attemptId: successfulAttemptId,
		canMarkNotHandled: true,
		createdAt: Date.UTC(2026, 7, 20, 16),
		messageCount: 3,
		outputKind: 'clipboard_markdown' as const,
		repeatedFromAttemptId: null,
		sessionId: annotationSessionId,
		state: 'succeeded' as const,
		updatedAt: Date.UTC(2026, 7, 20, 16),
	};
}

function savedMessage(props: {
	readonly body: string;
	readonly handled: boolean;
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
		handled: props.handled,
		savedBody: props.body,
	};
}

function outputSummary(
	outputKind: 'clipboard_markdown' | 'json_file',
	messageCount = 2,
): {
	readonly attemptId: string;
	readonly destinationFilename: string | null;
	readonly messageCount: number;
	readonly outputKind: 'clipboard_markdown' | 'json_file';
	readonly sessionId: string;
} {
	return {
		attemptId: successfulAttemptId,
		destinationFilename: outputKind === 'json_file' ? 'comments.json' : null,
		messageCount,
		outputKind,
		sessionId: annotationSessionId,
	} as const;
}

function findLastOperation(
	surface: RecordingAnnotationBrowserSurface,
	kind: 'output.handled.clear' | 'output.scope.commit',
): BridgeProductWorktreeAnnotationOperation | undefined {
	return surface.sentOperations.findLast((operation): boolean => operation.kind === kind);
}

function requireShareScopeButton(
	labelPrefix: 'All comments' | 'Pending comments',
): HTMLButtonElement {
	const button = document.querySelector<HTMLButtonElement>(`button[aria-label^="${labelPrefix},"]`);
	if (button !== null) return button;
	const availableLabels = [...document.querySelectorAll<HTMLElement>('button[aria-label]')].map(
		(candidate) => candidate.getAttribute('aria-label'),
	);
	throw new Error(
		`Expected ${labelPrefix} scope button. Available button labels: ${JSON.stringify(availableLabels)}.`,
	);
}

function outputHandledClearOperations(
	surface: RecordingAnnotationBrowserSurface,
): readonly Extract<
	BridgeProductWorktreeAnnotationOperation,
	{ readonly kind: 'output.handled.clear' }
>[] {
	return surface.sentOperations.filter(
		(
			operation,
		): operation is Extract<
			BridgeProductWorktreeAnnotationOperation,
			{ readonly kind: 'output.handled.clear' }
		> => operation.kind === 'output.handled.clear',
	);
}

function isToastAction(value: unknown): value is {
	readonly action: { readonly onClick: () => void };
} {
	if (typeof value !== 'object' || value === null || !('action' in value)) return false;
	const action = value.action;
	return (
		typeof action === 'object' &&
		action !== null &&
		'onClick' in action &&
		typeof action.onClick === 'function'
	);
}

async function performBrowserAction(action: () => Promise<void> | void): Promise<void> {
	await act(async (): Promise<void> => {
		await action();
		await settleInteraction();
	});
}

async function settleInteraction(): Promise<void> {
	await Promise.resolve();
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
	await Promise.resolve();
}

async function finishShareShelfMotion(shelf: HTMLElement): Promise<void> {
	await waitForShareShelfEndingStyle(shelf);
	const animations = shelf.getAnimations({ subtree: true });
	for (const animation of animations) animation.finish();
	await Promise.all(animations.map((animation) => animation.finished.catch((): void => {})));
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
	await Promise.resolve();
}

async function waitForShareShelfEndingStyle(
	shelf: HTMLElement,
	remainingFrames = 10,
): Promise<void> {
	if (!shelf.isConnected || shelf.hasAttribute('data-ending-style')) return;
	if (remainingFrames <= 0) throw new Error('Share shelf did not enter its closing transition.');
	await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
	await waitForShareShelfEndingStyle(shelf, remainingFrames - 1);
}

function requireHtmlElement(element: HTMLElement | SVGElement): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected an HTML element.');
	return element;
}

function clickHtmlButton(element: HTMLElement | SVGElement): void {
	if (!(element instanceof HTMLButtonElement)) throw new Error('Expected an HTML button.');
	element.click();
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

const unavailableContext: WorktreeAnnotationThreadContext = {
	...locatedContext,
	path: 'Sources/App/Unavailable.swift',
	placement: 'unavailable',
	threadId: unavailableThreadId,
};
