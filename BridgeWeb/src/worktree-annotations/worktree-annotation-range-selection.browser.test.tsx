import { parseDiffFromFile } from '@pierre/diffs';
import { act } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';
import { userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import { createBridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeMainCodeViewItem } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import {
	BridgeFileViewerCodePanel,
	type BridgeFileViewerSelectedCodeViewItem,
} from '../file-viewer/bridge-file-viewer-code-panel.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import { BridgeCodeViewPanel } from '../review-viewer/code-view/bridge-code-view-panel.js';
import { buildBridgeReviewProjection } from '../review-viewer/navigation/review-projection.js';
import {
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionSummary,
	annotationSessionId,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import { WorktreeAnnotationSurfaceProvider } from './worktree-annotation-surface-provider.js';

describe('worktree annotation Pierre range selection', () => {
	afterEach(async (): Promise<void> => {
		await cleanup();
	});

	test('paints a dragged File range, keeps its endpoint utility, and clears on Escape', async () => {
		const surface = new RecordingAnnotationBrowserSurface('fileView');
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
		await settleBrowserCondition(
			(): boolean => queryPierreElements('[data-column-number]').length >= 5,
			'Expected Pierre File line-number rows.',
		);
		const startRow = requireHTMLElement(
			queryPierreElements('[data-column-number="2"]')[0] ?? null,
			'Expected line 2 gutter row.',
		);
		const endRow = requireHTMLElement(
			queryPierreElements('[data-column-number="5"]')[0] ?? null,
			'Expected line 5 gutter row.',
		);
		const startBounds = startRow.getBoundingClientRect();
		const endBounds = endRow.getBoundingClientRect();

		await act(async (): Promise<void> => {
			dispatchPointer(startRow, 'pointerdown', {
				clientX: startBounds.left + 4,
				clientY: startBounds.top + startBounds.height / 2,
				pointerId: 17,
				pointerType: 'mouse',
			});
			dispatchPointer(document, 'pointermove', {
				clientX: endBounds.left + 4,
				clientY: endBounds.top + endBounds.height / 2,
				pointerId: 17,
				pointerType: 'mouse',
			});
			await nextAnimationFrame();
		});

		expect(queryPierreElements('[data-selected-line]').length).toBeGreaterThan(0);

		await act(async (): Promise<void> => {
			dispatchPointer(document, 'pointerup', {
				clientX: endBounds.left + 4,
				clientY: endBounds.top + endBounds.height / 2,
				pointerId: 17,
				pointerType: 'mouse',
			});
			await nextAnimationFrame();
		});
		expect(queryPierreElements('[data-selected-line]').length).toBeGreaterThan(0);
		expect(queryPierreElements('[data-utility-button]')).toHaveLength(1);
		expect(
			document.querySelectorAll('[aria-label="Write an annotation in Markdown"]'),
		).toHaveLength(0);

		const endpointUtility = requireHTMLElement(
			queryPierreElements('[data-utility-button]')[0] ?? null,
			'Expected the selected-range endpoint utility.',
		);
		const endpointBounds = endpointUtility.getBoundingClientRect();
		await act(async (): Promise<void> => {
			dispatchPointer(endpointUtility, 'pointerdown', {
				clientX: endpointBounds.left + endpointBounds.width / 2,
				clientY: endpointBounds.top + endpointBounds.height / 2,
				pointerId: 20,
				pointerType: 'mouse',
			});
			dispatchPointer(document, 'pointerup', {
				clientX: endpointBounds.left + endpointBounds.width / 2,
				clientY: endpointBounds.top + endpointBounds.height / 2,
				pointerId: 20,
				pointerType: 'mouse',
			});
			await nextAnimationFrame();
		});
		expect(
			document.querySelectorAll('[aria-label="Write an annotation in Markdown"]'),
		).toHaveLength(1);

		await act(async (): Promise<void> => {
			document.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true, key: 'Escape' }));
			await nextAnimationFrame();
		});
		expect(queryPierreElements('[data-selected-line]')).toHaveLength(0);

		const refreshedStartRow = requireHTMLElement(
			queryPierreElements('[data-column-number="2"]')[0] ?? null,
			'Expected refreshed line 2 gutter row.',
		);
		const refreshedStartBounds = refreshedStartRow.getBoundingClientRect();
		await act(async (): Promise<void> => {
			dispatchPointer(refreshedStartRow, 'pointermove', {
				clientX: refreshedStartBounds.left + 4,
				clientY: refreshedStartBounds.top + refreshedStartBounds.height / 2,
				pointerId: 18,
				pointerType: 'mouse',
			});
			await nextAnimationFrame();
		});
		const singleLineUtility = requireHTMLElement(
			queryPierreElements('[data-utility-button]')[0] ?? null,
			'Expected the single-line gutter utility.',
		);
		const utilityBounds = singleLineUtility.getBoundingClientRect();
		await act(async (): Promise<void> => {
			dispatchPointer(singleLineUtility, 'pointerdown', {
				clientX: utilityBounds.left + utilityBounds.width / 2,
				clientY: utilityBounds.top + utilityBounds.height / 2,
				pointerId: 19,
				pointerType: 'mouse',
			});
			dispatchPointer(document, 'pointerup', {
				clientX: utilityBounds.left + utilityBounds.width / 2,
				clientY: utilityBounds.top + utilityBounds.height / 2,
				pointerId: 19,
				pointerType: 'mouse',
			});
			await nextAnimationFrame();
		});
		expect(document.querySelector('[aria-label="Write an annotation in Markdown"]')).not.toBeNull();

		await act(async (): Promise<void> => {
			document.body.dispatchEvent(
				new PointerEvent('pointerdown', { bubbles: true, cancelable: true, pointerType: 'mouse' }),
			);
			await nextAnimationFrame();
		});
		expect(queryPierreElements('[data-selected-line]')).toHaveLength(0);
		expect(document.querySelector('[aria-label="Write an annotation in Markdown"]')).toBeNull();
	});

	test('paints and retains a dragged Review range through the shared React selection contract', async () => {
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
					<BridgeCodeViewPanel
						presentationPositionKey="annotation-range-review"
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
			await settleBrowserCondition(
				(): boolean => reviewAdditionRows().length >= 3,
				'Expected Pierre Review addition gutter rows.',
			);
			const rows = reviewAdditionRows();
			const startRow = requireHTMLElement(rows[0] ?? null, 'Expected first Review addition row.');
			const endRow = requireHTMLElement(rows[2] ?? null, 'Expected third Review addition row.');
			const startBounds = startRow.getBoundingClientRect();
			const endBounds = endRow.getBoundingClientRect();

			await act(async (): Promise<void> => {
				dispatchPointer(startRow, 'pointerdown', {
					clientX: startBounds.left + 4,
					clientY: startBounds.top + startBounds.height / 2,
					pointerId: 27,
					pointerType: 'mouse',
				});
				dispatchPointer(document, 'pointermove', {
					clientX: endBounds.left + 4,
					clientY: endBounds.top + endBounds.height / 2,
					pointerId: 27,
					pointerType: 'mouse',
				});
				await nextAnimationFrame();
			});
			expect(queryPierreElements('[data-selected-line]').length).toBeGreaterThan(0);

			await act(async (): Promise<void> => {
				dispatchPointer(document, 'pointerup', {
					clientX: endBounds.left + 4,
					clientY: endBounds.top + endBounds.height / 2,
					pointerId: 27,
					pointerType: 'mouse',
				});
				await nextAnimationFrame();
			});
			expect(queryPierreElements('[data-selected-line]').length).toBeGreaterThan(0);
			expect(queryPierreElements('[data-utility-button]')).toHaveLength(1);

			const endpointUtility = requireHTMLElement(
				queryPierreElements('[data-utility-button]')[0] ?? null,
				'Expected the Review selected-range endpoint utility.',
			);
			const endpointBounds = endpointUtility.getBoundingClientRect();
			await act(async (): Promise<void> => {
				dispatchPointer(endpointUtility, 'pointerdown', {
					clientX: endpointBounds.left + endpointBounds.width / 2,
					clientY: endpointBounds.top + endpointBounds.height / 2,
					pointerId: 28,
					pointerType: 'mouse',
				});
				dispatchPointer(document, 'pointerup', {
					clientX: endpointBounds.left + endpointBounds.width / 2,
					clientY: endpointBounds.top + endpointBounds.height / 2,
					pointerId: 28,
					pointerType: 'mouse',
				});
				await nextAnimationFrame();
			});
			const composerBeforeDurableProjection = document.querySelector<HTMLTextAreaElement>(
				'[aria-label="Write an annotation in Markdown"]',
			);
			if (composerBeforeDurableProjection === null) {
				throw new Error('Expected the Review root composer before durable projection.');
			}
			const saveButton = rendered.getByRole('button', { name: 'Save annotation' }).element();
			expect(saveButton.classList).toContain('text-primary');
			expect(saveButton.classList).not.toContain('bg-primary');
			expect(saveButton.querySelector('svg')?.classList).toContain('lucide-check');
			await act(async (): Promise<void> => {
				await rendered
					.getByRole('textbox', { name: 'Write an annotation in Markdown' })
					.fill('Split projection Save');
				await rendered.getByRole('button', { name: 'Save annotation' }).click();
			});
			await settleBrowserCondition(
				(): boolean => surface.sentOperations.some((operation) => operation.kind === 'root.create'),
				'Expected split Review Save to create a durable root draft.',
			);
			await expect
				.element(rendered.getByRole('button', { name: 'Saving annotation' }))
				.toBeDisabled();
			const createOperation = surface.sentOperations.find(
				(operation) => operation.kind === 'root.create',
			);
			if (createOperation?.kind !== 'root.create') throw new Error('Expected root.create.');
			await act(async (): Promise<void> => {
				surface.settleMostRecentCommittedWithoutProjection();
				await settleBrowserCondition(
					(): boolean =>
						surface.sentOperations.some((operation) => operation.kind === 'draft.save'),
					'Expected root.create receipt to continue directly to draft.save without projection.',
				);
			});
			await expect
				.element(rendered.getByRole('button', { name: 'Saving annotation' }))
				.toBeDisabled();
			await act(async (): Promise<void> => {
				surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'draft.save');
				await nextAnimationFrame();
				await nextAnimationFrame();
				const operationError = document.querySelector('[role="alert"]')?.textContent;
				if (operationError !== undefined) throw new Error(operationError);
			});
			await expect.element(rendered.getByText('Split projection Save')).toBeVisible();
			expect(
				document.querySelector('[data-testid="worktree-annotation-committed-pending-projection"]'),
			).not.toBeNull();
			expect(document.querySelector('[aria-label="Write an annotation in Markdown"]')).toBeNull();
			const codeRowAfterSave = requireHTMLElement(
				reviewAdditionRows()[1] ?? null,
				'Expected a Review code row after the committed Save receipt.',
			);
			const codeRowAfterSaveBounds = codeRowAfterSave.getBoundingClientRect();
			await act(async (): Promise<void> => {
				dispatchPointer(codeRowAfterSave, 'pointerdown', {
					clientX: codeRowAfterSaveBounds.left + 4,
					clientY: codeRowAfterSaveBounds.top + codeRowAfterSaveBounds.height / 2,
					pointerId: 29,
					pointerType: 'mouse',
				});
				dispatchPointer(document, 'pointerup', {
					clientX: codeRowAfterSaveBounds.left + 4,
					clientY: codeRowAfterSaveBounds.top + codeRowAfterSaveBounds.height / 2,
					pointerId: 29,
					pointerType: 'mouse',
				});
				await nextAnimationFrame();
			});
			await expect.element(rendered.getByText('Split projection Save')).toBeVisible();
			expect(
				document.querySelector('[data-testid="worktree-annotation-committed-pending-projection"]'),
			).not.toBeNull();
			await act(async (): Promise<void> => {
				surface.publishProjectionState({
					expectedThreadCount: 1,
					revision: 5,
					sessions: [annotationSessionSummary({ revision: 5, sessionId: annotationSessionId })],
				});
				surface.publishThread({
					context: {
						diffSide: 'additions',
						endLine: createOperation.origin.endLine,
						path: createOperation.origin.path,
						placement: 'exact',
						resolution: 'open',
						scope: 'located',
						sourceIdentity: createOperation.origin.sourceIdentity,
						sourceRole: 'review_head',
						startLine: createOperation.origin.startLine,
						threadId: annotationHeadThreadId,
					},
					message: {
						...annotationMessage({
							messageId: '00000000-0000-7000-8000-000000000031',
							sessionRevision: 5,
							threadId: annotationHeadThreadId,
						}),
						draft: null,
						savedBody: 'Split projection Save',
						savedRevision: 1,
					},
				});
				await nextAnimationFrame();
				await nextAnimationFrame();
			});
			await settleBrowserCondition(
				(): boolean =>
					document.querySelector(
						'[data-testid="worktree-annotation-committed-pending-projection"]',
					) === null,
				'Expected authoritative M1 to replace the committed receipt presentation.',
			);
			await expect.element(rendered.getByText('Split projection Save')).toBeVisible();
			const installedThread = rendered.getByTestId('worktree-annotation-thread').element();
			expect(installedThread.contains(document.activeElement)).toBe(true);
			await act(async (): Promise<void> => {
				await userEvent.keyboard('r');
			});
			await expect
				.element(rendered.getByRole('textbox', { name: 'Reply with Markdown' }))
				.toBeVisible();
			expect(
				surface.sentOperations
					.map((operation) => operation.kind)
					.filter((kind) => ['draft.edit.release', 'draft.save', 'root.create'].includes(kind)),
			).toEqual(['root.create', 'draft.save']);
		} finally {
			coordinator.dispose();
		}
	});
});

function reviewAdditionRows(): Element[] {
	return queryPierreElements('[data-column-number]').filter(
		(element): boolean => element.closest('[data-additions]') !== null,
	);
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

function makeFileItem(): BridgeFileViewerSelectedCodeViewItem {
	return {
		bridgeMetadata: {
			cacheKey: 'file-cache-file-1',
			contentRoles: ['file'],
			contentState: 'hydrated',
			displayPath: 'Sources/App/View.swift',
			itemId: 'file-1',
			lineCount: 8,
			sourceDescriptorId: 'descriptor-file-1',
		},
		file: {
			cacheKey: 'file-cache-file-1',
			contents: Array.from(
				{ length: 8 },
				(_unused, index): string => `let line${index + 1} = ${index + 1}`,
			).join('\n'),
			lang: 'swift',
			name: 'Sources/App/View.swift',
		},
		id: 'file:file-1',
		type: 'file',
		version: 1,
	};
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

function requireHTMLElement(value: Element | null, message: string): HTMLElement {
	if (!(value instanceof HTMLElement)) throw new Error(message);
	return value;
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

async function nextAnimationFrame(): Promise<void> {
	await new Promise<void>((resolve): void => {
		requestAnimationFrame((): void => resolve());
	});
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
