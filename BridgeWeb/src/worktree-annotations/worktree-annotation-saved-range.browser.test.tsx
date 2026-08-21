import { CodeView, parseDiffFromFile } from '@pierre/diffs';
import { act } from 'react';
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
import { WorktreeAnnotationSurfaceProvider } from './worktree-annotation-surface-provider.js';

describe.sequential('saved annotation range activation', () => {
	test('focuses the saved File range without opening or scrolling', async () => {
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
			const scrollCallCountBeforeFocus = scrollCalls.length;

			await act(async (): Promise<void> => {
				if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
				await Promise.resolve();
				commentSurface.focus();
				await Promise.resolve();
			});
			await settleBrowserCondition(
				(): boolean =>
					document
						.querySelector('[data-worktree-annotation-interaction]')
						?.getAttribute('data-annotation-active') === 'true',
				'Expected focus to activate the saved File thread.',
			);
			await settleBrowserCondition(
				(): boolean =>
					selectedLineCalls.some(
						(selection): boolean =>
							selection?.id === 'file:file-1' &&
							selection.range.start === 4 &&
							selection.range.end === 7,
					),
				'Expected focus to publish the complete saved File range.',
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

	test('focuses the saved Review range without opening or scrolling', async () => {
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
			const scrollCallCountBeforeFocus = scrollCalls.length;

			await act(async (): Promise<void> => {
				if (document.activeElement instanceof HTMLElement) document.activeElement.blur();
				await Promise.resolve();
				commentSurface.focus();
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
				'Expected focus to publish the complete saved Review range.',
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
