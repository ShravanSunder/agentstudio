import { CodeView, parseDiffFromFile, type CodeViewOptions } from '@pierre/diffs';
import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import { createBridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeMainCodeViewItem } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import { BridgeFileViewerCodePanel } from '../file-viewer/bridge-file-viewer-code-panel.js';
import type { BridgeFileViewerSelectedCodeViewItem } from '../file-viewer/bridge-file-viewer-code-view-items.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import { BridgeCodeViewPanel } from '../review-viewer/code-view/bridge-code-view-panel.js';
import { buildBridgeReviewProjection } from '../review-viewer/navigation/review-projection.js';
import {
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	annotationSessionSummary,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import type { WorktreeAnnotationThreadContext } from './worktree-annotation-surface-client.js';
import {
	useWorktreeAnnotationInteraction,
	WorktreeAnnotationSurfaceProvider,
} from './worktree-annotation-surface-provider.js';

describe.sequential('saved annotation range activation', () => {
	test('keeps a newly saved one-message File thread active after Save', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const appliedOptions: CodeViewOptions<undefined>[] = [];
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetOptions = CodeView.prototype.setOptions;
		CodeView.prototype.setOptions = function captureOptions(
			options: CodeViewOptions<undefined> | undefined,
		): void {
			if (options !== undefined) appliedOptions.push(options);
			originalSetOptions.call(this, options);
		};
		const selectedCodeViewItem = makeFileItem();

		try {
			const rendered = await render(
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<InteractionStateProbe />
					<BridgeFileViewerCodePanel
						codeViewWorkerPoolEnabled={false}
						openFileState={{
							displayItem: null,
							fileId: 'file-1',
							path: 'Sources/App/View.swift',
							status: 'ready',
						}}
						renderFulfillmentCoordinator={{
							observePostRender: (): void => {},
							reconcilePublication: (): void => {},
						}}
						selectedCodeViewItem={selectedCodeViewItem}
						totalHeightPixels={null}
					/>
				</WorktreeAnnotationSurfaceProvider>,
			);
			await settleBrowserCondition(
				(): boolean => appliedOptions.at(-1)?.onGutterUtilityClick !== undefined,
				'Expected File Pierre gutter callback.',
			);
			await act(async (): Promise<void> => {
				invokeGutterAdmission(
					requireCodeViewOptions(appliedOptions.at(-1)),
					{ end: 7, start: 4 },
					selectedCodeViewItem,
				);
				await Promise.resolve();
			});
			const composer = rendered.getByRole('textbox', {
				name: 'Write an annotation in Markdown',
			});
			await act(async (): Promise<void> => {
				await composer.fill('One saved root comment');
			});
			await settleBrowserCondition(
				(): boolean => surface.sentOperations.some((operation) => operation.kind === 'root.create'),
				'Expected root.create before Save.',
			);
			const rootCreate = surface.sentOperations.find(
				(operation) => operation.kind === 'root.create',
			);
			if (rootCreate?.kind !== 'root.create') throw new Error('Expected root.create operation.');
			await act(async (): Promise<void> => {
				surface.settleMostRecentCommitted(annotationSessionId, 1);
				surface.publishThread({
					context: fileRangeContext,
					message: {
						...annotationMessage({
							messageId: savedRootMessageId,
							threadId: annotationHeadThreadId,
						}),
						draft: {
							activeEditToken: rootCreate.editToken,
							body: 'One saved root comment',
							revision: 0,
						},
						savedBody: null,
						savedRevision: null,
					},
				});
				await Promise.resolve();
			});
			await act(async (): Promise<void> => {
				composer.element().dispatchEvent(
					new KeyboardEvent('keydown', {
						bubbles: true,
						key: 'Enter',
						metaKey: true,
					}),
				);
				await Promise.resolve();
			});
			await settleBrowserCondition(
				(): boolean => surface.sentOperations.some((operation) => operation.kind === 'draft.save'),
				'Expected draft.save for the one-message root.',
			);
			await act(async (): Promise<void> => {
				surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'draft.save');
				surface.publishProjectionState({
					expectedThreadCount: 1,
					revision: 3,
					sessions: [annotationSessionSummary({ revision: 3, sessionId: annotationSessionId })],
				});
				surface.publishThread({
					context: fileRangeContext,
					message: {
						...annotationMessage({
							messageId: savedRootMessageId,
							sessionRevision: 3,
							threadId: annotationHeadThreadId,
						}),
						draft: null,
						messageRevision: 1,
						savedBody: 'One saved root comment',
						savedRevision: 1,
					},
				});
				await Promise.resolve();
			});
			await settleBrowserCondition(
				(): boolean =>
					document.querySelector('[data-testid="annotation-interaction-state"]')?.textContent ===
					`savedThread:${annotationHeadThreadId}`,
				'Expected the saved one-message thread to remain active after Save.',
			);
		} finally {
			CodeView.prototype.setOptions = originalSetOptions;
		}
	});

	test('keeps File focus inert and activates the saved range on click without scrolling', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
		const selectedLineCalls: Parameters<CodeView['setSelectedLines']>[0][] = [];
		const scrollCalls: Parameters<CodeView['scrollTo']>[0][] = [];
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetSelectedLines = CodeView.prototype.setSelectedLines;
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalScrollTo = CodeView.prototype.scrollTo;
		CodeView.prototype.setSelectedLines = function captureSelectedLines(
			selection: Parameters<CodeView['setSelectedLines']>[0],
		): void {
			selectedLineCalls.push(selection);
			originalSetSelectedLines.call(this, selection);
		};
		CodeView.prototype.scrollTo = function captureScroll(
			target: Parameters<CodeView['scrollTo']>[0],
		): void {
			scrollCalls.push(target);
			originalScrollTo.call(this, target);
		};

		try {
			await render(
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<BridgeFileViewerCodePanel
						codeViewWorkerPoolEnabled={false}
						openFileState={{
							displayItem: null,
							fileId: 'file-1',
							path: 'Sources/App/View.swift',
							status: 'ready',
						}}
						renderFulfillmentCoordinator={{
							observePostRender: (): void => {},
							reconcilePublication: (): void => {},
						}}
						selectedCodeViewItem={makeFileItem()}
						totalHeightPixels={null}
					/>
				</WorktreeAnnotationSurfaceProvider>,
			);
			await publishSavedThread(surface, fileRangeContext);
			const commentSurface = await stableAnnotationInteractionSurface(
				'Expected the stable saved File comment surface.',
			);
			const selectedLineCallCountBeforeFocus = selectedLineCalls.length;
			const scrollCallCountBeforeFocus = scrollCalls.length;

			await act(async (): Promise<void> => {
				commentSurface.dispatchEvent(new FocusEvent('focusin', { bubbles: true }));
				await Promise.resolve();
			});
			expect(commentSurface.getAttribute('data-annotation-active')).toBe('false');
			expect(selectedLineCalls).toHaveLength(selectedLineCallCountBeforeFocus);

			await act(async (): Promise<void> => {
				commentSurface.click();
				await Promise.resolve();
			});
			await settleBrowserCondition(
				(): boolean =>
					document
						.querySelector('[data-worktree-annotation-interaction]')
						?.getAttribute('data-annotation-active') === 'true',
				'Expected click to activate the saved File thread.',
			);
			await settleBrowserCondition(
				(): boolean =>
					selectedLineCalls.some(
						(selection): boolean =>
							selection?.id === 'file:file-1' &&
							selection.range.start === 4 &&
							selection.range.end === 7,
					),
				'Expected click to publish the complete saved File range.',
			);

			expect(selectedLineCalls).toContainEqual({
				id: 'file:file-1',
				range: { end: 7, start: 4 },
			});
			expect(scrollCalls).toHaveLength(scrollCallCountBeforeFocus);
			expect(document.querySelector('[data-annotation-expanded="true"]')).toBeNull();
			expect(document.querySelector('[aria-label^="Show source range"]')).toBeNull();
		} finally {
			CodeView.prototype.setSelectedLines = originalSetSelectedLines;
			CodeView.prototype.scrollTo = originalScrollTo;
		}
	});

	test('keeps Review focus inert and activates the saved range on click without scrolling', async () => {
		const surface = new RecordingAnnotationBrowserSurface('review');
		const selectedLineCalls: Parameters<CodeView['setSelectedLines']>[0][] = [];
		const scrollCalls: Parameters<CodeView['scrollTo']>[0][] = [];
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetSelectedLines = CodeView.prototype.setSelectedLines;
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalScrollTo = CodeView.prototype.scrollTo;
		CodeView.prototype.setSelectedLines = function captureSelectedLines(
			selection: Parameters<CodeView['setSelectedLines']>[0],
		): void {
			selectedLineCalls.push(selection);
			originalSetSelectedLines.call(this, selection);
		};
		CodeView.prototype.scrollTo = function captureScroll(
			target: Parameters<CodeView['scrollTo']>[0],
		): void {
			scrollCalls.push(target);
			originalScrollTo.call(this, target);
		};
		const reviewPackage = makeBridgeReviewPackage();
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		const coordinator = createBridgeMainRenderFulfillmentCoordinator({
			sendDisposition: (): void => {},
		});
		const reviewCodeViewItem = makeReviewCodeViewItem();

		try {
			await render(
				<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
					<BridgeCodeViewPanel
						presentationPositionKey="annotation-saved-range-review"
						projection={projection}
						renderFulfillmentCoordinator={coordinator}
						reviewPackage={reviewPackage}
						selectedCodeViewItem={reviewCodeViewItem}
						selectedItemId="item-source"
						visibleCodeViewItems={[reviewCodeViewItem]}
						workerPoolEnabled={false}
					/>
				</WorktreeAnnotationSurfaceProvider>,
			);
			await publishSavedThread(surface, reviewRangeContext);
			const commentSurface = await stableAnnotationInteractionSurface(
				'Expected the stable saved Review comment surface.',
			);
			const selectedLineCallCountBeforeFocus = selectedLineCalls.length;
			const scrollCallCountBeforeFocus = scrollCalls.length;

			await act(async (): Promise<void> => {
				commentSurface.dispatchEvent(new FocusEvent('focusin', { bubbles: true }));
				await Promise.resolve();
			});
			expect(commentSurface.getAttribute('data-annotation-active')).toBe('false');
			expect(selectedLineCalls).toHaveLength(selectedLineCallCountBeforeFocus);

			await act(async (): Promise<void> => {
				commentSurface.click();
				await Promise.resolve();
			});

			const expectedRange = {
				end: 2,
				endSide: 'additions',
				side: 'additions',
				start: 2,
			} as const;
			await settleBrowserCondition(
				(): boolean =>
					selectedLineCalls.some(
						(selection): boolean =>
							selection?.id === 'item-source' &&
							selection.range.start === 2 &&
							selection.range.end === 2,
					),
				'Expected click to publish the complete saved Review range.',
			);
			expect(selectedLineCalls).toContainEqual({ id: 'item-source', range: expectedRange });
			expect(scrollCalls).toHaveLength(scrollCallCountBeforeFocus);
			expect(document.querySelector('[data-annotation-expanded="true"]')).toBeNull();
			expect(document.querySelector('[aria-label^="Show source range"]')).toBeNull();
		} finally {
			CodeView.prototype.setSelectedLines = originalSetSelectedLines;
			CodeView.prototype.scrollTo = originalScrollTo;
			coordinator.dispose();
		}
	});
});

async function publishSavedThread(
	surface: RecordingAnnotationBrowserSurface,
	context: WorktreeAnnotationThreadContext,
): Promise<void> {
	await act(async (): Promise<void> => {
		surface.publishProjectionState({
			expectedThreadCount: 1,
			revision: 3,
			sessions: [annotationSessionSummary({ revision: 3, sessionId: annotationSessionId })],
		});
		surface.publishThread({
			context,
			message: annotationMessage({
				messageId: '00000000-0000-7000-8000-000000000091',
				sessionRevision: 3,
				threadId: annotationHeadThreadId,
			}),
		});
		await Promise.resolve();
	});
}

const fileRangeContext: WorktreeAnnotationThreadContext = {
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

const reviewRangeContext: WorktreeAnnotationThreadContext = {
	diffSide: 'additions',
	endLine: 2,
	path: 'Sources/App/View.swift',
	placement: 'exact',
	resolution: 'open',
	scope: 'located',
	sourceIdentity: 'handle-item-source-head',
	sourceRole: 'review_head',
	startLine: 2,
	threadId: annotationHeadThreadId,
};

const savedRootMessageId = '00000000-0000-7000-8000-000000000031';

function makeFileItem(): BridgeFileViewerSelectedCodeViewItem {
	return {
		bridgeMetadata: {
			cacheKey: 'file-cache-1',
			contentRoles: ['file'],
			contentState: 'hydrated',
			displayPath: 'Sources/App/View.swift',
			itemId: 'file-1',
			lineCount: 8,
			sourceDescriptorId: 'descriptor-file-1',
		},
		file: {
			cacheKey: 'file-cache-1',
			contents: Array.from(
				{ length: 8 },
				(_, index): string => `let line${index + 1} = ${index + 1}`,
			).join('\n'),
			lang: 'swift',
			name: 'Sources/App/View.swift',
		},
		id: 'file:file-1',
		type: 'file',
		version: 1,
	};
}

function makeReviewCodeViewItem(): BridgeMainCodeViewItem {
	return {
		bridgeMetadata: {
			cacheKey: 'review-base|review-head',
			contentRoles: ['base', 'head'],
			contentState: 'hydrated',
			displayPath: 'Sources/App/View.swift',
			itemId: 'item-source',
			lineCount: 3,
		},
		fileDiff: parseDiffFromFile(
			{
				cacheKey: 'review-base',
				contents: ['let stable = 1', 'let reviewed = "before"', 'let tail = 3'].join('\n'),
				name: 'Sources/App/View.swift',
			},
			{
				cacheKey: 'review-head',
				contents: ['let stable = 1', 'let reviewed = "after"', 'let tail = 3'].join('\n'),
				name: 'Sources/App/View.swift',
			},
		),
		id: 'item-source',
		type: 'diff',
		version: 1,
	};
}

function invokeGutterAdmission(
	options: CodeViewOptions<undefined>,
	range: { readonly end: number; readonly start: number },
	item: Readonly<{ id: string }>,
): void {
	const gutterCallback = options.onGutterUtilityClick;
	const selectionEndCallback = options.onLineSelectionEnd;
	if (gutterCallback === undefined || selectionEndCallback === undefined) {
		throw new Error('Expected Pierre gutter and line-selection callbacks.');
	}
	Reflect.apply(gutterCallback, undefined, [range, { item }]);
	Reflect.apply(selectionEndCallback, undefined, [range, { item }]);
}

function requireCodeViewOptions(
	value: CodeViewOptions<undefined> | undefined,
): CodeViewOptions<undefined> {
	if (value === undefined) throw new Error('Expected current Pierre options.');
	return value;
}

function InteractionStateProbe(): ReactElement {
	const interaction = useWorktreeAnnotationInteraction();
	const presentation = interaction.pierreRangePresentation;
	return (
		<span data-testid="annotation-interaction-state">
			{presentation.kind === 'savedThread'
				? `${presentation.kind}:${presentation.threadId}`
				: presentation.kind}
		</span>
	);
}

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

async function stableAnnotationInteractionSurface(failureMessage: string): Promise<HTMLElement> {
	let previousSurface: HTMLElement | null = null;
	let stableFrameCount = 0;
	await settleBrowserCondition((): boolean => {
		const currentSurface = document.querySelector<HTMLElement>(
			'[data-worktree-annotation-interaction]',
		);
		if (currentSurface === null || !currentSurface.isConnected) {
			previousSurface = null;
			stableFrameCount = 0;
			return false;
		}
		if (currentSurface === previousSurface) stableFrameCount += 1;
		else {
			previousSurface = currentSurface;
			stableFrameCount = 0;
		}
		return stableFrameCount >= 2;
	}, failureMessage);
	if (previousSurface === null) throw new Error(failureMessage);
	return previousSurface;
}
