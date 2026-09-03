import {
	CodeView,
	parseDiffFromFile,
	type CodeViewItem,
	type CodeViewOptions,
} from '@pierre/diffs';
import { act, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../app/bridge-app.css';
import { createBridgeMainRenderFulfillmentCoordinator } from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeMainCodeViewItem } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import {
	makeBridgeReviewItem,
	makeBridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import { BridgeCodeViewPanel } from '../review-viewer/code-view/bridge-code-view-panel.js';
import { buildBridgeReviewProjection } from '../review-viewer/navigation/review-projection.js';
import {
	annotationHeadThreadId,
	annotationMessage,
	annotationSessionId,
	RecordingAnnotationBrowserSurface,
} from './worktree-annotation-browser-test-support.js';
import type { WorktreeAnnotationThreadContext } from './worktree-annotation-surface-client.js';
import { WorktreeAnnotationSurfaceProvider } from './worktree-annotation-surface-provider.js';
import { WorktreeAnnotationNewMessageComposer } from './worktree-annotation-thread.js';

const predecessorPublicationIdentity = {
	generation: 7,
	packageId: 'package-predecessor',
	publicationId: '00000000-0000-7000-8000-000000000041',
	revision: 3,
	sourceIdentity: 'source-predecessor',
} as const;

describe('worktree annotation Review publication continuity', () => {
	test('pairs a predecessor composer origin with the installed predecessor publication', async () => {
		// Arrange
		const surface = new RecordingAnnotationBrowserSurface('review');
		surface.setReviewActiveIdentity(predecessorPublicationIdentity);
		const renderedView = await render(<PredecessorReviewComposer surface={surface} />);

		// Act
		await act(async (): Promise<void> => {
			await renderedView
				.getByRole('textbox', { name: 'Write an annotation in Markdown' })
				.fill('Comment that remains bound to the displayed Review publication.');
			await settleBrowserInteraction();
		});
		await waitForRootCreate(surface);

		// Assert
		const rootOperationIndex = surface.sentOperations.findIndex(
			(operation) => operation.kind === 'root.create',
		);
		const rootOperation = surface.sentOperations[rootOperationIndex];
		expect(rootOperation).toMatchObject({
			kind: 'root.create',
			origin: { sourceIdentity: 'handle-item-source-head-predecessor' },
		});
		expect(surface.sentReviewPublicationIdentities[rootOperationIndex]).toEqual({
			packageId: 'package-predecessor',
			publicationId: '00000000-0000-7000-8000-000000000041',
			reviewGeneration: 7,
			revision: 3,
			sourceIdentity: 'source-predecessor',
		});
	});

	test('reattaches one durable root composer after the Review panel is replaced', async () => {
		// Arrange
		const surface = new RecordingAnnotationBrowserSurface('review');
		const mountedCodeViews: CodeView[] = [];
		const appliedOptions: CodeViewOptions<undefined>[] = [];
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetup = CodeView.prototype.setup;
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetOptions = CodeView.prototype.setOptions;
		CodeView.prototype.setup = function captureMountedCodeView(root: HTMLElement): void {
			mountedCodeViews.push(this);
			originalSetup.call(this, root);
		};
		CodeView.prototype.setOptions = function captureOptions(
			options: CodeViewOptions<undefined> | undefined,
		): void {
			if (options !== undefined) appliedOptions.push(options);
			originalSetOptions.call(this, options);
		};
		const predecessorPackage = reviewPackageForItem('item-predecessor', 7);
		const successorPackage = reviewPackageForItem('item-successor', 8);
		const predecessorItem = reviewCodeViewItem('item-predecessor', 7);
		const successorItem = reviewCodeViewItem('item-successor', 8);
		const coordinator = createBridgeMainRenderFulfillmentCoordinator({
			sendDisposition: (): void => {},
		});
		const renderPublication = (
			reviewPackage: BridgeReviewPackage,
			selectedCodeViewItem: BridgeMainCodeViewItem | null,
		): ReactElement => (
			<WorktreeAnnotationSurfaceProvider surfaceClient={surface.client}>
				{selectedCodeViewItem === null ? (
					<div data-testid="review-publication-fallback" />
				) : (
					<BridgeCodeViewPanel
						presentationPositionKey="annotation-publication-continuity"
						projection={buildBridgeReviewProjection({
							reviewPackage,
							request: { facets: [], mode: { kind: 'normalReview' } },
						})}
						renderFulfillmentCoordinator={coordinator}
						reviewPackage={reviewPackage}
						selectedCodeViewItem={selectedCodeViewItem}
						selectedItemId={selectedCodeViewItem.id}
						visibleCodeViewItems={[selectedCodeViewItem]}
						workerPoolEnabled={false}
					/>
				)}
			</WorktreeAnnotationSurfaceProvider>
		);

		try {
			const rendered = await render(renderPublication(predecessorPackage, predecessorItem));
			await settleBrowserCondition(
				(): boolean => mountedCodeViews[0]?.getItem('item-predecessor') !== undefined,
				'Expected the predecessor Review item to mount.',
			);
			await act(async (): Promise<void> => {
				surface.publishProjection(1, 0);
				await settleBrowserInteraction();
			});
			const predecessorCodeView = requireCodeView(mountedCodeViews[0]);
			const predecessorPierreItem = requireCodeViewItem(
				predecessorCodeView.getItem('item-predecessor'),
			);
			await act(async (): Promise<void> => {
				invokeGutterAdmission(
					requireCodeViewOptions(appliedOptions.at(-1)),
					{ end: 2, side: 'additions', start: 2 },
					predecessorPierreItem,
				);
				await settleBrowserInteraction();
			});
			const composer = rendered.getByRole('textbox', {
				name: 'Write an annotation in Markdown',
			});
			await act(async (): Promise<void> => {
				await composer.fill('Draft retained through Review replacement.');
				await settleBrowserInteraction();
			});
			await waitForRootCreate(surface);
			const rootCreate = surface.sentOperations.find(
				(operation) => operation.kind === 'root.create',
			);
			if (rootCreate?.kind !== 'root.create') throw new Error('Expected root.create operation.');
			await act(async (): Promise<void> => {
				surface.settleMostRecentCommittedWithoutProjection(annotationSessionId, 'root.create');
				await settleBrowserInteraction();
			});
			// Act
			let itemIdentityUpdated = false;
			await act(async (): Promise<void> => {
				itemIdentityUpdated = predecessorCodeView.updateItemId(
					'item-predecessor',
					'item-successor',
				);
				await settleBrowserInteraction();
			});
			expect(itemIdentityUpdated).toBe(true);
			await rendered.rerender(renderPublication(predecessorPackage, null));
			await settleBrowserInteraction();
			await rendered.rerender(renderPublication(successorPackage, successorItem));
			await settleBrowserCondition(
				(): boolean => mountedCodeViews[1]?.getItem('item-successor') !== undefined,
				'Expected the successor Review item to mount.',
			);
			await act(async (): Promise<void> => {
				surface.publishProjection(2, 1);
				surface.publishThread({
					context: annotationContext(),
					message: {
						...annotationMessage({
							messageId: '00000000-0000-7000-8000-000000000031',
							sessionRevision: 2,
							threadId: annotationHeadThreadId,
						}),
						draft: {
							activeEditToken: rootCreate.editToken,
							body: 'Draft retained through Review replacement.',
							revision: 0,
						},
						savedBody: null,
						savedRevision: null,
					},
				});
				await settleBrowserInteraction();
			});

			// Assert
			await settleBrowserCondition(
				(): boolean =>
					document.querySelector<HTMLTextAreaElement>(
						'[aria-label="Write an annotation in Markdown"]',
					)?.value === 'Draft retained through Review replacement.',
				'Expected the successor Review item to reclaim the durable root composer.',
			);
			expect(
				surface.sentOperations.filter((operation) => operation.kind === 'root.create'),
			).toHaveLength(1);
			expect(
				surface.sentOperations.filter((operation) => operation.kind === 'draft.edit.release'),
			).toHaveLength(0);
		} finally {
			CodeView.prototype.setup = originalSetup;
			CodeView.prototype.setOptions = originalSetOptions;
			coordinator.dispose();
		}
	});
});

function reviewPackageForItem(itemId: string, generation: number): BridgeReviewPackage {
	const basePackage = makeBridgeReviewPackage();
	const item = makeBridgeReviewItem({ itemId, path: 'Sources/App/View.swift' });
	return {
		...basePackage,
		packageId: `package-${generation}`,
		reviewGeneration: generation,
		revision: generation,
		orderedItemIds: [itemId],
		itemsById: { [itemId]: item },
	};
}

function reviewCodeViewItem(itemId: string, generation: number): BridgeMainCodeViewItem {
	const baseContents = ['let stable = 1', 'let reviewed = "before"', 'let tail = 3'].join('\n');
	const headContents = ['let stable = 1', 'let reviewed = "after"', 'let tail = 3'].join('\n');
	return {
		bridgeMetadata: {
			cacheKey: `${itemId}-base|${itemId}-head`,
			contentRoles: ['base', 'head'],
			contentState: 'hydrated',
			displayPath: 'Sources/App/View.swift',
			itemId,
			lineCount: 3,
			sourceDescriptorIdsByRole: {
				base: `handle-${itemId}-base-${generation}`,
				diff: null,
				file: null,
				head: `handle-${itemId}-head-${generation}`,
			},
		},
		fileDiff: parseDiffFromFile(
			{ cacheKey: `${itemId}-base`, contents: baseContents, name: 'Sources/App/View.swift' },
			{ cacheKey: `${itemId}-head`, contents: headContents, name: 'Sources/App/View.swift' },
		),
		id: itemId,
		type: 'diff',
		version: generation,
	};
}

function annotationContext(): WorktreeAnnotationThreadContext {
	return {
		diffSide: 'additions',
		endLine: 2,
		path: 'Sources/App/View.swift',
		placement: 'exact',
		resolution: 'open',
		scope: 'located',
		sourceIdentity: 'handle-item-predecessor-head-7',
		sourceRole: 'review_head',
		startLine: 2,
		threadId: annotationHeadThreadId,
	};
}

function invokeGutterAdmission(
	options: CodeViewOptions<undefined>,
	range: { readonly end: number; readonly side: 'additions'; readonly start: number },
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

function requireCodeView(value: CodeView | undefined): CodeView {
	if (value === undefined) throw new Error('Expected mounted Pierre CodeView.');
	return value;
}

function requireCodeViewItem(value: CodeViewItem | undefined): CodeViewItem {
	if (value === undefined) throw new Error('Expected mounted Pierre item.');
	return value;
}

function requireCodeViewOptions(
	value: CodeViewOptions<undefined> | undefined,
): CodeViewOptions<undefined> {
	if (value === undefined) throw new Error('Expected current Pierre options.');
	return value;
}

async function settleBrowserCondition(
	predicate: () => boolean,
	failureMessage: string,
	remainingFrames = 60,
): Promise<void> {
	await act(async (): Promise<void> => settleBrowserInteraction());
	if (predicate()) return;
	if (remainingFrames <= 0) throw new Error(failureMessage);
	await settleBrowserCondition(predicate, failureMessage, remainingFrames - 1);
}

function PredecessorReviewComposer(props: {
	readonly surface: RecordingAnnotationBrowserSurface;
}): ReactElement {
	return (
		<WorktreeAnnotationSurfaceProvider surfaceClient={props.surface.client}>
			<WorktreeAnnotationNewMessageComposer
				createOperation={(body, editToken, admission) => ({
					admission: admission ?? { kind: 'implicitOrSingle' },
					body,
					editToken,
					kind: 'root.create',
					origin: {
						diffSide: 'additions',
						endLine: 2,
						kind: 'located',
						path: 'Sources/App/View.swift',
						sourceIdentity: 'handle-item-source-head-predecessor',
						sourceRole: 'reviewHead',
						startLine: 2,
					},
				})}
				onCancel={() => {}}
				onSaved={() => {}}
				placeholder="Write an annotation in Markdown"
			/>
		</WorktreeAnnotationSurfaceProvider>
	);
}

async function waitForRootCreate(surface: RecordingAnnotationBrowserSurface): Promise<void> {
	for (let attempt = 0; attempt < 50; attempt += 1) {
		if (surface.sentOperations.some((operation) => operation.kind === 'root.create')) return;
		// eslint-disable-next-line no-await-in-loop -- Browser state must settle between bounded observations.
		await act(async (): Promise<void> => settleBrowserInteraction());
	}
	throw new Error('Expected one Review root.create operation.');
}

async function settleBrowserInteraction(): Promise<void> {
	await Promise.resolve();
	await new Promise<void>((resolve): void => {
		requestAnimationFrame((): void => resolve());
	});
	await Promise.resolve();
}
