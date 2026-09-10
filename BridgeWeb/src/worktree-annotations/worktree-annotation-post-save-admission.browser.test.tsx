import {
	CodeView,
	parseDiffFromFile,
	type CodeViewOptions,
	type SelectedLineRange,
} from '@pierre/diffs';
import { act, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';
import { userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import { createBridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeMainCodeViewItem } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import { BridgeCodeViewPanel } from '../review-viewer/code-view/bridge-code-view-panel.js';
import { buildBridgeReviewProjection } from '../review-viewer/navigation/review-projection.js';
import {
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import { WorktreeAnnotationSurfaceProvider } from './worktree-annotation-surface-provider.js';
import { useWorktreeAnnotationProjection } from './worktree-annotation-surface-provider.js';

const rootComposerSelector = '[aria-label="Write an annotation in Markdown"]';

describe('worktree annotation post-Save admission', () => {
	afterEach(async (): Promise<void> => {
		await cleanup();
	});

	test('admits a second Review root on a new range while projection is unavailable', async () => {
		const gutterAdmissions: SelectedLineRange[] = [];
		const lineSelectionAdmissions: SelectedLineRange[] = [];
		// oxlint-disable-next-line unbound-method -- Restored below; invoked with its original receiver.
		const originalSetOptions = CodeView.prototype.setOptions;
		CodeView.prototype.setOptions = function recordPierreAdmissions(
			options: CodeViewOptions<undefined>,
		): void {
			const onGutterUtilityClick = options.onGutterUtilityClick;
			const onLineSelectionEnd = options.onLineSelectionEnd;
			originalSetOptions.call(this, {
				...options,
				onGutterUtilityClick: (range, context): void => {
					gutterAdmissions.push({ ...range });
					if (context.type === 'file') onGutterUtilityClick?.(range, context);
					else onGutterUtilityClick?.(range, context);
				},
				onLineSelectionEnd: (range, context): void => {
					if (range !== null) lineSelectionAdmissions.push({ ...range });
					if (context.type === 'file') onLineSelectionEnd?.(range, context);
					else onLineSelectionEnd?.(range, context);
				},
			});
		};
		const surface = new RecordingAnnotationBrowserSurface('review');
		const reviewPackage = makeBridgeReviewPackage();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const coordinator = createBridgeMainRenderFulfillmentCoordinator({
			sendDisposition: (): void => {},
		});
		const reviewItem = makeReviewItem();
		try {
			const rendered = await render(
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<CommandConfirmedProjectionProbe />
					<BridgeCodeViewPanel
						presentationPositionKey="annotation-post-save-admission-review"
						projection={projection}
						renderFulfillmentCoordinator={coordinator}
						reviewPackage={reviewPackage}
						selectedCodeViewItem={reviewItem}
						selectedItemId="item-source"
						visibleCodeViewItems={[reviewItem]}
						workerPoolEnabled={false}
					/>
				</WorktreeAnnotationSurfaceProvider>,
			);
			await act(async (): Promise<void> => {
				surface.publishProjectionState({
					expectedThreadCount: 0,
					revision: 1,
					sessions: [annotationSessionSummary({ revision: 1, sessionId: annotationSessionId })],
				});
				await settleBrowserInteraction();
			});
			await settleBrowserCondition(
				(): boolean => reviewRows('additions').length >= 3 && reviewRows('deletions').length >= 3,
				'Expected Pierre Review split gutter rows.',
			);

			const firstRangeRow = requireHTMLElement(
				reviewRows('additions')[0] ?? null,
				'Expected the first Review addition row.',
			);
			await hoverReviewRowAndClickUtility(firstRangeRow, '1', 30);
			expect(gutterAdmissions).toEqual([{ end: 1, side: 'additions', start: 1 }]);
			await act(async (): Promise<void> => {
				await rendered
					.getByRole('textbox', { name: 'Write an annotation in Markdown' })
					.fill('First command-confirmed Save');
				await rendered.getByRole('button', { name: 'Save annotation' }).click();
			});
			await settleBrowserCondition(
				(): boolean => surface.sentOperations.some((operation) => operation.kind === 'root.create'),
				'Expected the first root.create operation.',
			);
			await act(async (): Promise<void> => {
				surface.settleMostRecentCommittedWithoutProjection();
				await settleBrowserInteraction();
			});
			await settleBrowserCondition(
				(): boolean => surface.sentOperations.some((operation) => operation.kind === 'draft.save'),
				'Expected the root receipt to continue to draft.save.',
			);
			await act(async (): Promise<void> => {
				surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'draft.save');
				surface.publishUnavailable();
				await settleBrowserInteraction();
			});

			expect(
				rendered
					.getByTestId('command-confirmed-projection-probe')
					.element()
					.getAttribute('data-count'),
			).toBe('1');
			await settleBrowserCondition(
				(): boolean => document.body.textContent?.includes('First command-confirmed Save') ?? false,
				'Expected the command-confirmed saved body to render.',
			);
			expect(document.body.textContent).toContain('First command-confirmed Save');
			expect(
				surface.sentOperations
					.map((operation) => operation.kind)
					.filter((kind) => kind === 'root.create' || kind === 'draft.save'),
			).toEqual(['root.create', 'draft.save']);
			expect(document.querySelector(rootComposerSelector)).toBeNull();
			const commandConfirmedThread = requireHTMLElement(
				queryPierreElements('[data-testid="worktree-annotation-thread"]')[0] ?? null,
				'Expected the command-confirmed Review thread before exact projection.',
			);
			const replyButton = rendered.getByRole('button', { name: 'Reply to annotation thread' });
			await expect.element(replyButton).toBeVisible();
			await expect.element(replyButton).toBeEnabled();
			await act(async (): Promise<void> => {
				await userEvent.click(replyButton.element());
				await settleBrowserInteraction();
			});
			await settleBrowserCondition(
				(): boolean =>
					queryPierreElements('[aria-label="Reply with Markdown"]').some((element): boolean => {
						const bounds = element.getBoundingClientRect();
						return bounds.width > 0 && bounds.height > 0;
					}),
				'Expected the command-confirmed Reply composer to survive before exact projection.',
			);
			expect(commandConfirmedThread.getAttribute('data-annotation-expanded')).toBe('true');
			await act(async (): Promise<void> => {
				await userEvent.keyboard('{Escape}');
				await settleBrowserInteraction();
			});
			await settleBrowserCondition(
				(): boolean => queryPierreElements('[aria-label="Reply with Markdown"]').length === 0,
				'Expected the pre-projection Reply composer to close before the second root.',
			);

			const secondRangeRow = requireHTMLElement(
				reviewRows('deletions')[2] ?? null,
				'Expected the third Review deletion row after Save.',
			);
			await selectReviewRow(secondRangeRow, 'deletions', 32);
			expect(lineSelectionAdmissions.at(-1)).toEqual({
				end: 3,
				side: 'deletions',
				start: 3,
			});
			expect(document.body.textContent).toContain('First command-confirmed Save');

			const refreshedSecondRangeRow = requireHTMLElement(
				reviewRows('deletions')[2] ?? null,
				'Expected the third Review deletion row before its second root gesture.',
			);
			await hoverReviewRowAndClickUtility(refreshedSecondRangeRow, '3', 34);
			expect(gutterAdmissions).toEqual([
				{ end: 1, side: 'additions', start: 1 },
				{ end: 3, side: 'deletions', start: 3 },
			]);
			expect(document.body.textContent).toContain('First command-confirmed Save');
			await settleBrowserCondition(
				(): boolean => document.querySelector(rootComposerSelector) !== null,
				'Expected the second Review root composer on deletion line 3 after Save.',
			);
			await act(async (): Promise<void> => {
				await settleBrowserInteraction();
				await rendered.unmount();
				await settleBrowserInteraction();
			});
		} finally {
			await act(async (): Promise<void> => {
				CodeView.prototype.setOptions = originalSetOptions;
				coordinator.dispose();
				await settleBrowserInteraction();
			});
		}
	});
});

function CommandConfirmedProjectionProbe(): ReactElement {
	const projection = useWorktreeAnnotationProjection();
	const thread = projection.commandConfirmedThreads[0];
	return (
		<output
			data-count={projection.commandConfirmedThreads.length}
			data-draft={thread?.messages[0]?.draft === null ? 'none' : 'present'}
			data-path={thread?.context.path}
			data-source-identity={thread?.context.sourceIdentity}
			data-source-role={thread?.context.sourceRole}
			data-testid="command-confirmed-projection-probe"
			hidden
		/>
	);
}

function reviewRows(side: 'additions' | 'deletions'): Element[] {
	return queryPierreElements('[data-column-number]').filter(
		(element): boolean => element.closest(`[data-${side}]`) !== null,
	);
}

async function selectReviewRow(
	row: HTMLElement,
	side: 'additions' | 'deletions',
	pointerId: number,
): Promise<void> {
	const rowBounds = row.getBoundingClientRect();
	await act(async (): Promise<void> => {
		dispatchPointer(row, 'pointerdown', pointerAtLeftGutter(rowBounds, pointerId));
		await nextAnimationFrame();
	});
	const rowAfterPointerDown = requireHTMLElement(
		reviewRows(side)[2] ?? null,
		'Expected the intended Review row after pointerdown publication.',
	);
	const finalRowBounds = rowAfterPointerDown.getBoundingClientRect();
	await act(async (): Promise<void> => {
		dispatchPointer(
			rowAfterPointerDown,
			'pointerup',
			pointerAtLeftGutter(finalRowBounds, pointerId),
		);
		await nextAnimationFrame();
	});
}

async function hoverReviewRowAndClickUtility(
	row: HTMLElement,
	expectedLineNumber: string,
	pointerId: number,
): Promise<void> {
	const rowBounds = row.getBoundingClientRect();
	await act(async (): Promise<void> => {
		dispatchPointer(row, 'pointermove', pointerAtLeftGutter(rowBounds, pointerId));
		await nextAnimationFrame();
	});
	const utility = requireUtilityOnLine(expectedLineNumber);
	const utilityBounds = utility.getBoundingClientRect();
	await act(async (): Promise<void> => {
		dispatchPointer(utility, 'pointerdown', pointerAtCenter(utilityBounds, pointerId + 1));
		await nextAnimationFrame();
	});
	const utilityAfterPointerDown = requireUtilityOnLine(expectedLineNumber);
	const finalUtilityBounds = utilityAfterPointerDown.getBoundingClientRect();
	await act(async (): Promise<void> => {
		dispatchPointer(
			utilityAfterPointerDown,
			'pointerup',
			pointerAtCenter(finalUtilityBounds, pointerId + 1),
		);
		await nextAnimationFrame();
	});
}

function requireUtilityOnLine(lineNumber: string): HTMLElement {
	return requireHTMLElement(
		queryPierreElements('[data-utility-button]').find(
			(candidate): boolean =>
				candidate.closest('[data-column-number]')?.getAttribute('data-column-number') ===
				lineNumber,
		) ?? null,
		`Expected the Review root utility on line ${lineNumber}.`,
	);
}

function dispatchPointer(
	target: EventTarget,
	type: 'pointerdown' | 'pointermove' | 'pointerup',
	init: PointerEventInit,
): void {
	target.dispatchEvent(
		new PointerEvent(type, { bubbles: true, cancelable: true, composed: true, ...init }),
	);
}

function pointerAtLeftGutter(bounds: DOMRect, pointerId: number): PointerEventInit {
	return {
		clientX: bounds.left + 4,
		clientY: bounds.top + bounds.height / 2,
		pointerId,
		pointerType: 'mouse',
	};
}

function pointerAtCenter(bounds: DOMRect, pointerId: number): PointerEventInit {
	return {
		clientX: bounds.left + bounds.width / 2,
		clientY: bounds.top + bounds.height / 2,
		pointerId,
		pointerType: 'mouse',
	};
}

function queryPierreElements(selector: string): Element[] {
	const elements: Element[] = [];
	const pendingRoots: ParentNode[] = [document];
	while (pendingRoots.length > 0) {
		const root = pendingRoots.shift();
		if (root === undefined) break;
		elements.push(...root.querySelectorAll(selector));
		for (const candidate of root.querySelectorAll('*')) {
			if (candidate.shadowRoot !== null) pendingRoots.push(candidate.shadowRoot);
		}
	}
	return elements;
}

function requireHTMLElement(value: Element | null, message: string): HTMLElement {
	if (!(value instanceof HTMLElement)) throw new Error(message);
	return value;
}

async function nextAnimationFrame(): Promise<void> {
	await new Promise<void>((resolve): void => {
		requestAnimationFrame((): void => resolve());
	});
}

async function settleBrowserInteraction(): Promise<void> {
	await Promise.resolve();
	await nextAnimationFrame();
	await Promise.resolve();
	await nextAnimationFrame();
	await Promise.resolve();
}

async function settleBrowserCondition(
	predicate: () => boolean,
	failureMessage: string,
	remainingFrames = 60,
): Promise<void> {
	await act(async (): Promise<void> => {
		await nextAnimationFrame();
	});
	if (predicate()) return;
	if (remainingFrames <= 0) throw new Error(failureMessage);
	await settleBrowserCondition(predicate, failureMessage, remainingFrames - 1);
}

function makeReviewItem(): BridgeMainCodeViewItem {
	const baseContents = ['let stable = 1', 'let reviewed = "before"', 'let tail = 3'].join('\n');
	const headContents = ['let stable = 1', 'let reviewed = "after"', 'let tail = 3'].join('\n');
	return {
		bridgeMetadata: {
			cacheKey: 'review-base|review-head',
			contentRoles: ['base', 'head'],
			contentState: 'hydrated',
			displayPath: 'Sources/App/View.swift',
			itemId: 'item-source',
			lineCount: 3,
			sourceDescriptorIdsByRole: {
				base: 'handle-item-source-base',
				diff: null,
				file: null,
				head: 'handle-item-source-head',
			},
		},
		fileDiff: parseDiffFromFile(
			{ cacheKey: 'review-base', contents: baseContents, name: 'Sources/App/View.swift' },
			{ cacheKey: 'review-head', contents: headContents, name: 'Sources/App/View.swift' },
		),
		id: 'item-source',
		type: 'diff',
		version: 1,
	};
}
