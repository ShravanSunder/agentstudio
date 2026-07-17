import {
	CodeView,
	parseDiffFromFile,
	type CodeViewDiffItem,
	type CodeViewItem,
	type CodeViewOptions,
	type PostRenderPhase,
} from '@pierre/diffs';
import { act } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../../app/bridge-app.css';
import { prepareBridgeMainPierreItemForPresentation } from '../../core/comm-worker/bridge-main-pierre-item-adapter.js';
import {
	createBridgeMainRenderFulfillmentCoordinator,
	type BridgeMainRenderPublicationItem,
} from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import {
	bridgeWorkerReviewPierreRenderJobEventSchema,
	type BridgeWorkerReviewPierreRenderJobEvent,
} from '../../core/comm-worker/bridge-worker-contracts.js';
import { buildBridgeWorkerPierreRenderJob } from '../../core/comm-worker/bridge-worker-pierre-render-job.js';
import type { BridgeWorkerRenderDispositionReceipt } from '../../core/comm-worker/bridge-worker-render-fulfillment.js';
import { makeBridgeWorkerRenderReceiptIdentity } from '../../core/comm-worker/bridge-worker-render-fulfillment.test-support.js';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import { buildBridgeReviewProjection } from '../navigation/review-projection.js';
import { bridgePierreOptionalHighlightLanguage } from '../workers/pierre/bridge-pierre-language-normalization.js';
import { BridgeCodeViewPanel } from './bridge-code-view-panel.js';

type ExactReviewPierreDiffItem = Extract<
	BridgeMainRenderPublicationItem,
	{ readonly type: 'diff' }
> &
	CodeViewDiffItem;

interface CapturedBridgeCodeViewPostRender {
	readonly contextItem: CodeViewItem;
	readonly invoke: (props: {
		readonly contextItem?: CodeViewItem;
		readonly phase: PostRenderPhase;
	}) => void;
}

interface PendingAnimationFrame {
	readonly callback: FrameRequestCallback;
	readonly frameHandle: number;
}

describe('BridgeCodeViewPanel render fulfillment', () => {
	test('adapts Review items with main versions, preserves collapse, and reuses exact painted residency', async () => {
		// Arrange: hold Pierre's public post-render callback so every fulfillment transition is
		// deterministic, while retaining a real mounted CodeView and its public readback APIs.
		const mountedCodeView: { current: CodeView | null } = { current: null };
		const capturedPostRenders: CapturedBridgeCodeViewPostRender[] = [];
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetup = CodeView.prototype.setup;
		// oxlint-disable-next-line unbound-method -- Browser witness restores the exact prototype method.
		const originalSetOptions = CodeView.prototype.setOptions;
		CodeView.prototype.setup = function captureMountedCodeView(root: HTMLElement): void {
			mountedCodeView.current = this;
			originalSetup.call(this, root);
		};
		CodeView.prototype.setOptions = function capturePostRender(
			options: CodeViewOptions<undefined> | undefined,
		): void {
			const onPostRender = options?.onPostRender;
			if (onPostRender === undefined) {
				originalSetOptions.call(this, options);
				return;
			}
			const capturedOptions = {
				...options,
				onPostRender: (...callbackArguments: readonly unknown[]): void => {
					captureBridgeCodeViewPostRender({
						callback: onPostRender,
						callbackArguments,
						invocations: capturedPostRenders,
					});
				},
			} satisfies CodeViewOptions<undefined>;
			originalSetOptions.call(this, capturedOptions);
		};

		const dispositions: BridgeWorkerRenderDispositionReceipt[] = [];
		const pendingAnimationFrames: PendingAnimationFrame[] = [];
		let nextFrameHandle = 1;
		let nowMilliseconds = 1_000;
		const renderFulfillmentCoordinator = createBridgeMainRenderFulfillmentCoordinator({
			cancelAnimationFrame: (frameHandle): void => {
				const frameIndex = pendingAnimationFrames.findIndex(
					(frame): boolean => frame.frameHandle === frameHandle,
				);
				if (frameIndex >= 0) pendingAnimationFrames.splice(frameIndex, 1);
			},
			nowMilliseconds: (): number => {
				nowMilliseconds += 1;
				return nowMilliseconds;
			},
			requestAnimationFrame: (callback): number => {
				const frameHandle = nextFrameHandle;
				nextFrameHandle += 1;
				pendingAnimationFrames.push({ callback, frameHandle });
				return frameHandle;
			},
			sendDisposition: (receipt): void => {
				dispositions.push(receipt);
			},
		});
		const firstPublication = makeReviewPublication({
			contentsMarker: 'first-attempt',
			publicationSequence: 1,
			version: 37,
		});
		const firstPublicationItem = requireExactReviewPierreDiffItem(
			firstPublication.job.payload.item,
		);
		const defaultReviewPackage = makeBridgeReviewPackage();
		const defaultReviewItem = defaultReviewPackage.itemsById['item-source'];
		if (defaultReviewItem === undefined) {
			throw new Error('Expected the Review fixture descriptor.');
		}
		const reviewPackage = {
			...defaultReviewPackage,
			itemsById: {
				...defaultReviewPackage.itemsById,
				'item-source': { ...defaultReviewItem, additions: 17, deletions: 9 },
			},
			summary: { ...defaultReviewPackage.summary, additions: 17, deletions: 9 },
		};
		const projection = buildBridgeReviewProjection({
			reviewPackage,
			request: { facets: [], mode: { kind: 'normalReview' } },
		});
		renderFulfillmentCoordinator.acceptPublication(firstPublication);
		const firstControllerPreparedItem = prepareBridgeMainPierreItemForPresentation({
			currentItem: undefined,
			presentationItem: firstPublicationItem,
		});
		const firstControllerSeedItem = firstControllerPreparedItem.item;
		renderFulfillmentCoordinator.bindPublicationItem({
			finalItem: firstControllerSeedItem,
			publicationItem: firstPublicationItem,
			residency: firstControllerPreparedItem.residency,
		});
		renderFulfillmentCoordinator.markPublicationQueued(firstPublication);
		expect(dispositionKinds(dispositions)).toEqual(['queued']);

		const panelProps = {
			presentationPositionKey: 'render-fulfillment-position',
			projection,
			renderFulfillmentCoordinator,
			reviewPackage,
			selectedCodeViewItem: firstControllerSeedItem,
			selectedItemId: firstPublicationItem.id,
			visibleCodeViewItems: [firstControllerSeedItem],
			workerPoolEnabled: false,
		};
		const rendered = render(<BridgeCodeViewPanel {...panelProps} />);

		try {
			await settleBridgeCodeViewState((): boolean => {
				const currentItem = mountedCodeView.current?.getItem(firstPublicationItem.id);
				return (
					currentItem !== undefined &&
					isExactReviewPierreDiffItem(currentItem) &&
					currentItem !== firstPublicationItem &&
					currentItem.bridgeMetadata.cacheKey === firstPublicationItem.bridgeMetadata.cacheKey
				);
			}, 'Expected Pierre current item to become the first main-adapted Review object.');
			const firstCodeView = requireMountedCodeView(mountedCodeView.current);
			const firstFinalItem = requireCurrentReviewPierreDiffItem(
				firstCodeView,
				firstPublicationItem.id,
			);
			expect(firstPublicationItem.version).toBe(37);
			expect(firstControllerSeedItem).not.toBe(firstPublicationItem);
			expect(firstControllerSeedItem.version).toBe(1);
			expect(firstFinalItem).not.toBe(firstPublicationItem);
			expect.soft(firstFinalItem.version).toBe(1);
			await settleBridgeCodeViewState(
				(): boolean =>
					firstCodeView
						.getRenderedItems()
						.some(
							(renderedItem): boolean =>
								renderedItem.id === firstFinalItem.id &&
								renderedItem.item === firstFinalItem &&
								renderedItem.element.isConnected,
						),
				'Expected Pierre rendered membership to carry the exact first final Review object.',
			);
			await settleBridgeCodeViewState(
				(): boolean => hasPostRenderForItem(capturedPostRenders, firstFinalItem),
				'Expected Pierre onPostRender callback for the exact first final Review object.',
			);
			await settleBridgeCodeViewState(
				(): boolean =>
					document.querySelector('[data-testid="bridge-code-view-header-metadata"]') !== null,
				'Expected the Bridge descriptor header metadata to render.',
			);
			const metadata = document.querySelector('[data-testid="bridge-code-view-header-metadata"]');
			if (!(metadata instanceof HTMLElement)) {
				throw new Error('Expected mounted Bridge descriptor header metadata.');
			}
			const metadataCounts = [...metadata.querySelectorAll(':scope > span')].filter(
				(element): boolean => element.textContent === '-9' || element.textContent === '+17',
			);
			expect(metadataCounts.map((element): string | null => element.textContent)).toEqual([
				'-9',
				'+17',
			]);
			for (const metadataCount of metadataCounts) {
				const metadataCountBox = metadataCount.getBoundingClientRect();
				expect(getComputedStyle(metadataCount).display).not.toBe('none');
				expect(metadataCountBox.width).toBeGreaterThan(0);
				expect(metadataCountBox.height).toBeGreaterThan(0);
			}
			const pierreContainer = document.querySelector('diffs-container');
			if (!(pierreContainer instanceof HTMLElement) || pierreContainer.shadowRoot === null) {
				throw new Error('Expected mounted Pierre diffs-container shadow DOM.');
			}
			const pierreAdditionCounters = [
				...pierreContainer.shadowRoot.querySelectorAll('[data-additions-count]'),
			];
			const pierreDeletionCounters = [
				...pierreContainer.shadowRoot.querySelectorAll('[data-deletions-count]'),
			];
			expect(pierreAdditionCounters).toHaveLength(1);
			expect(pierreDeletionCounters).toHaveLength(1);
			for (const pierreCounter of [...pierreAdditionCounters, ...pierreDeletionCounters]) {
				const counterBox = pierreCounter.getBoundingClientRect();
				expect(
					getComputedStyle(pierreCounter).display === 'none' ||
						counterBox.width === 0 ||
						counterBox.height === 0,
				).toBe(true);
			}
			const firstPostRender = requirePostRenderForItem(capturedPostRenders, firstFinalItem);

			// The exact main-adapted item is both Pierre's current record and rendered member. The raw
			// structured-clone publication cannot settle the attempt.
			expect(firstCodeView.getItem(firstFinalItem.id)).toBe(firstFinalItem);
			expect(
				firstCodeView
					.getRenderedItems()
					.find((renderedItem): boolean => renderedItem.id === firstFinalItem.id)?.item,
			).toBe(firstFinalItem);
			expect(dispositionKinds(dispositions)).toEqual(['queued']);
			await invokeCapturedPostRenderWithinAct({ invocation: firstPostRender, phase: 'unmount' });
			expect(dispositionKinds(dispositions)).toEqual(['queued']);
			await invokeCapturedPostRenderWithinAct({
				contextItem: firstPublicationItem,
				invocation: firstPostRender,
				phase: 'update',
			});
			expect(dispositionKinds(dispositions)).toEqual(['queued']);

			const wrongContextItem = copyItemWithVersion(firstFinalItem, 92);
			await invokeCapturedPostRenderWithinAct({
				contextItem: wrongContextItem,
				invocation: firstPostRender,
				phase: 'update',
			});
			expect(dispositionKinds(dispositions)).toEqual(['queued']);

			// Exact callback context alone is insufficient when public Pierre readback disagrees.
			await act(async (): Promise<void> => {
				firstCodeView.updateItem(wrongContextItem);
				await Promise.resolve();
			});
			expect(firstCodeView.getItem(firstPublicationItem.id)).toBe(wrongContextItem);
			await invokeCapturedPostRenderWithinAct({ invocation: firstPostRender, phase: 'update' });
			expect(dispositionKinds(dispositions)).toEqual(['queued']);
			await act(async (): Promise<void> => {
				firstCodeView.setItems([firstFinalItem]);
				await Promise.resolve();
			});
			await settleBridgeCodeViewState(
				(): boolean => firstCodeView.getItem(firstFinalItem.id) === firstFinalItem,
				'Expected Pierre current item identity to restore after wrong-current readback.',
			);

			const originalGetRenderedItems = firstCodeView.getRenderedItems.bind(firstCodeView);
			firstCodeView.getRenderedItems = (): [] => [];
			await invokeCapturedPostRenderWithinAct({ invocation: firstPostRender, phase: 'update' });
			expect(dispositionKinds(dispositions)).toEqual(['queued']);
			const connectedRenderedItems = originalGetRenderedItems();
			const matchingRenderedItem = connectedRenderedItems.find(
				(renderedItem): boolean => renderedItem.item === firstFinalItem,
			);
			if (matchingRenderedItem === undefined) {
				throw new Error('Expected real Pierre rendered membership for the first publication.');
			}
			firstCodeView.getRenderedItems = () => [
				{ ...matchingRenderedItem, element: document.createElement('div') },
			];
			await invokeCapturedPostRenderWithinAct({ invocation: firstPostRender, phase: 'update' });
			expect(dispositionKinds(dispositions)).toEqual(['queued']);
			firstCodeView.getRenderedItems = originalGetRenderedItems;

			// Only the exact final callback plus connected public readback advances fulfillment.
			await invokeCapturedPostRenderWithinAct({ invocation: firstPostRender, phase: 'update' });
			expect(dispositionKinds(dispositions)).toEqual(['queued', 'applied']);
			expect(pendingAnimationFrames).toHaveLength(1);
			expect(dispositionKinds(dispositions)).not.toContain('painted');
			const pendingPaintFrame = pendingAnimationFrames.shift();
			if (pendingPaintFrame === undefined) {
				throw new Error('Expected matching post-render readback to schedule paint validation.');
			}
			pendingPaintFrame.callback(nowMilliseconds);
			expect(dispositionKinds(dispositions)).toEqual(['queued', 'applied', 'painted']);

			// A real user collapse is local presentation state. A changed same-id publication must
			// preserve it while minting the next main-owned version.
			await act(async (): Promise<void> => {
				await rendered.getByRole('button', { name: 'Collapse file' }).click();
				await Promise.resolve();
			});
			await settleBridgeCodeViewState((): boolean => {
				const currentItem = firstCodeView.getItem(firstFinalItem.id);
				return (
					currentItem !== undefined &&
					isExactReviewPierreDiffItem(currentItem) &&
					currentItem !== firstFinalItem &&
					currentItem.collapsed === true
				);
			}, 'Expected the public Review collapse control to install one exact collapsed item.');
			const collapsedItem = requireCurrentReviewPierreDiffItem(firstCodeView, firstFinalItem.id);
			expect(collapsedItem.collapsed).toBe(true);
			expect(collapsedItem.version).toBe((firstFinalItem.version ?? 0) + 1);

			const secondPublication = makeReviewPublication({
				contentsMarker: 'second-attempt',
				publicationSequence: 2,
				version: 93,
			});
			const secondPublicationItem = requireExactReviewPierreDiffItem(
				secondPublication.job.payload.item,
			);
			expect(secondPublicationItem).not.toBe(firstPublicationItem);
			expect(secondPublicationItem.version).toBe(93);
			renderFulfillmentCoordinator.acceptPublication(secondPublication);
			renderFulfillmentCoordinator.markPublicationQueued(secondPublication);
			expect(dispositionKinds(dispositions)).toEqual(['queued', 'applied', 'painted']);
			await invokeCapturedPostRenderWithinAct({ invocation: firstPostRender, phase: 'update' });
			expect(dispositionKinds(dispositions)).toEqual(['queued', 'applied', 'painted']);

			const secondPanelProps = {
				...panelProps,
				selectedCodeViewItem: secondPublicationItem,
				visibleCodeViewItems: [secondPublicationItem],
			};
			await act(async (): Promise<void> => {
				rendered.rerender(<BridgeCodeViewPanel {...secondPanelProps} />);
				await Promise.resolve();
			});
			await settleBridgeCodeViewState((): boolean => {
				const currentItem = firstCodeView.getItem(secondPublicationItem.id);
				return (
					currentItem !== undefined &&
					isExactReviewPierreDiffItem(currentItem) &&
					currentItem !== secondPublicationItem &&
					currentItem.collapsed === true &&
					currentItem.bridgeMetadata.cacheKey === secondPublicationItem.bridgeMetadata.cacheKey
				);
			}, 'Expected Pierre current item to become the collapse-preserving second final object.');
			const secondFinalItem = requireCurrentReviewPierreDiffItem(
				firstCodeView,
				secondPublicationItem.id,
			);
			expect(secondFinalItem).not.toBe(secondPublicationItem);
			expect(secondFinalItem.collapsed).toBe(true);
			expect(secondFinalItem.version).toBe((collapsedItem.version ?? 0) + 1);
			await settleBridgeCodeViewState(
				(): boolean =>
					firstCodeView
						.getRenderedItems()
						.some(
							(renderedItem): boolean =>
								renderedItem.id === secondFinalItem.id &&
								renderedItem.item === secondFinalItem &&
								renderedItem.element.isConnected,
						),
				'Expected Pierre rendered membership to carry the exact second final Review object.',
			);
			await settleBridgeCodeViewState(
				(): boolean => hasPostRenderForItem(capturedPostRenders, secondFinalItem),
				'Expected Pierre onPostRender callback for the exact second final Review object.',
			);
			const secondPostRender = requirePostRenderForItem(capturedPostRenders, secondFinalItem);
			expect(dispositionKinds(dispositions)).toEqual(['queued', 'applied', 'painted', 'queued']);

			await invokeCapturedPostRenderWithinAct({ invocation: firstPostRender, phase: 'update' });
			expect
				.soft(dispositionKinds(dispositions))
				.toEqual(['queued', 'applied', 'painted', 'queued']);
			await invokeCapturedPostRenderWithinAct({ invocation: secondPostRender, phase: 'update' });
			expect(dispositionKinds(dispositions)).toEqual([
				'queued',
				'applied',
				'painted',
				'queued',
				'applied',
			]);
			expect(pendingAnimationFrames).toHaveLength(1);
			const secondPendingPaintFrame = pendingAnimationFrames.shift();
			if (secondPendingPaintFrame === undefined) {
				throw new Error('Expected the second exact Review attempt to schedule paint validation.');
			}
			secondPendingPaintFrame.callback(nowMilliseconds);
			expect(dispositionKinds(dispositions)).toEqual([
				'queued',
				'applied',
				'painted',
				'queued',
				'applied',
				'painted',
			]);

			// A fresh worker attempt with an equal final fingerprint binds to the exact connected
			// painted object and settles without asking Pierre for another content render.
			const retryPublication = cloneReviewPublicationForRetry(secondPublication);
			const retryPublicationItem = requireExactReviewPierreDiffItem(
				retryPublication.job.payload.item,
			);
			const secondFinalPostRenderCount = postRenderCountForItem(
				capturedPostRenders,
				secondFinalItem,
			);
			expect(retryPublicationItem).not.toBe(secondPublicationItem);
			renderFulfillmentCoordinator.acceptPublication(retryPublication);
			renderFulfillmentCoordinator.markPublicationQueued(retryPublication);
			expect(dispositionKinds(dispositions)).toEqual([
				'queued',
				'applied',
				'painted',
				'queued',
				'applied',
				'painted',
			]);
			await act(async (): Promise<void> => {
				rendered.rerender(
					<BridgeCodeViewPanel
						{...secondPanelProps}
						selectedCodeViewItem={retryPublicationItem}
						visibleCodeViewItems={[retryPublicationItem]}
					/>,
				);
				await Promise.resolve();
			});
			await settleBridgeCodeViewState(
				(): boolean => dispositionKinds(dispositions).at(-1) === 'applied',
				'Expected equal-fingerprint Review retry to reconcile from connected painted residency.',
			);
			expect(firstCodeView.getItem(secondFinalItem.id)).toBe(secondFinalItem);
			expect(
				firstCodeView
					.getRenderedItems()
					.find((renderedItem): boolean => renderedItem.id === secondFinalItem.id)?.item,
			).toBe(secondFinalItem);
			expect(postRenderCountForItem(capturedPostRenders, secondFinalItem)).toBe(
				secondFinalPostRenderCount,
			);
			expect(pendingAnimationFrames).toHaveLength(1);
			const retryPendingPaintFrame = pendingAnimationFrames.shift();
			if (retryPendingPaintFrame === undefined) {
				throw new Error('Expected reused Review residency to schedule paint validation.');
			}
			retryPendingPaintFrame.callback(nowMilliseconds);
			expect(dispositionKinds(dispositions)).toEqual([
				'queued',
				'applied',
				'painted',
				'queued',
				'applied',
				'painted',
				'queued',
				'applied',
				'painted',
			]);
		} finally {
			CodeView.prototype.setup = originalSetup;
			CodeView.prototype.setOptions = originalSetOptions;
			renderFulfillmentCoordinator.dispose();
		}
	});
});

function makeReviewPublication(props: {
	readonly contentsMarker: string;
	readonly publicationSequence: number;
	readonly version: number;
}): BridgeWorkerReviewPierreRenderJobEvent {
	const itemId = 'item-source';
	const baseCacheKey = `base-${props.contentsMarker}`;
	const headCacheKey = `head-${props.contentsMarker}`;
	const contentCacheKey = `${baseCacheKey}|${headCacheKey}`;
	const job = buildBridgeWorkerPierreRenderJob({
		bridgeDemandRank: { lane: 'selected', priority: props.publicationSequence },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
		contentCacheKey,
		contentHash: `sha256:${props.contentsMarker}`,
		itemId,
		language: 'swift',
		payload: {
			item: {
				bridgeMetadata: {
					cacheKey: contentCacheKey,
					contentRoles: ['base', 'head'],
					contentState: 'hydrated',
					displayPath: 'Sources/App/View.swift',
					itemId,
					lineCount: 2,
				},
				fileDiff: parseDiffFromFile(
					{
						cacheKey: baseCacheKey,
						contents: `let value = "base-${props.contentsMarker}"\n`,
						name: 'Sources/App/View.swift',
					},
					{
						cacheKey: headCacheKey,
						contents: `let value = "head-${props.contentsMarker}"\n`,
						name: 'Sources/App/View.swift',
					},
				),
				id: itemId,
				type: 'diff',
				version: props.version,
			},
			kind: 'codeViewDiffItem',
		},
		renderKind: 'reviewDiff',
		window: { endLine: 2, startLine: 1, totalLineCount: 2 },
	});
	return {
		direction: 'serverWorkerToMain',
		job,
		kind: 'reviewPierreRenderJob',
		publicationSequence: props.publicationSequence,
		renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
			itemId,
			publicationSequence: props.publicationSequence,
			surface: 'review',
			workerDerivationEpoch: 1,
		}),
		surface: 'review',
		transferDescriptors: [
			{
				byteLength: job.payloadByteLength,
				fieldPath: ['job', 'payload'],
				messageKind: 'reviewPierreRenderJob',
				mode: 'clone',
			},
		],
		wireVersion: 1,
		workerDerivationEpoch: 1,
	};
}

function cloneReviewPublicationForRetry(
	publication: BridgeWorkerReviewPierreRenderJobEvent,
): BridgeWorkerReviewPierreRenderJobEvent {
	const publicationItem = requireExactReviewPierreDiffItem(publication.job.payload.item);
	const clonedPublicationItem = {
		...publicationItem,
		bridgeMetadata: {
			...publicationItem.bridgeMetadata,
			contentRoles: [...publicationItem.bridgeMetadata.contentRoles],
		},
		fileDiff: { ...publicationItem.fileDiff },
	};
	return bridgeWorkerReviewPierreRenderJobEventSchema.parse({
		...publication,
		job: {
			...publication.job,
			payload: {
				...publication.job.payload,
				item: clonedPublicationItem,
			},
		},
		renderReceiptIdentity: {
			...publication.renderReceiptIdentity,
			attemptId: 'attempt-review-equal-fingerprint-retry',
		},
	});
}

function copyItemWithVersion(item: CodeViewItem, version: number): CodeViewItem {
	return { ...item, version };
}

function dispositionKinds(
	dispositions: readonly BridgeWorkerRenderDispositionReceipt[],
): readonly BridgeWorkerRenderDispositionReceipt['disposition'][] {
	return dispositions.map((receipt) => receipt.disposition);
}

async function invokeCapturedPostRenderWithinAct(props: {
	readonly contextItem?: CodeViewItem;
	readonly invocation: CapturedBridgeCodeViewPostRender;
	readonly phase: PostRenderPhase;
}): Promise<void> {
	await act(async (): Promise<void> => {
		props.invocation.invoke({
			phase: props.phase,
			...(props.contextItem === undefined ? {} : { contextItem: props.contextItem }),
		});
		await Promise.resolve();
	});
}

function requireMountedCodeView(codeView: CodeView | null): CodeView {
	if (codeView === null) {
		throw new Error('Expected production BridgeCodeViewPanel to mount a public Pierre CodeView.');
	}
	return codeView;
}

function requirePostRenderForItem(
	invocations: readonly CapturedBridgeCodeViewPostRender[],
	item: CodeViewItem,
): CapturedBridgeCodeViewPostRender {
	const invocation = invocations.find((candidate): boolean => candidate.contextItem === item);
	if (invocation === undefined) {
		throw new Error(`Expected Pierre onPostRender callback for exact item ${item.id}.`);
	}
	return invocation;
}

function hasPostRenderForItem(
	invocations: readonly CapturedBridgeCodeViewPostRender[],
	item: CodeViewItem,
): boolean {
	return invocations.some((candidate): boolean => candidate.contextItem === item);
}

function postRenderCountForItem(
	invocations: readonly CapturedBridgeCodeViewPostRender[],
	item: CodeViewItem,
): number {
	return invocations.filter((candidate): boolean => candidate.contextItem === item).length;
}

function captureBridgeCodeViewPostRender(props: {
	readonly callback: NonNullable<CodeViewOptions<undefined>['onPostRender']>;
	readonly callbackArguments: readonly unknown[];
	readonly invocations: CapturedBridgeCodeViewPostRender[];
}): void {
	const callbackArguments = requireBridgeCodeViewPostRenderArguments(props.callbackArguments);
	const capturedContextItem = callbackArguments.context.item;
	const capturedContext = { ...callbackArguments.context, item: capturedContextItem };
	props.invocations.push({
		contextItem: capturedContextItem,
		invoke: (invokeProps): void => {
			Reflect.apply(props.callback, undefined, [
				callbackArguments.element,
				callbackArguments.instance,
				invokeProps.phase,
				{
					...capturedContext,
					item: invokeProps.contextItem ?? capturedContextItem,
				},
			]);
		},
	});
}

function requireBridgeCodeViewPostRenderArguments(callbackArguments: readonly unknown[]): {
	readonly context: Readonly<Record<string, unknown>> & { readonly item: CodeViewItem };
	readonly element: HTMLElement;
	readonly instance: unknown;
} {
	const [element, instance, phase, context] = callbackArguments;
	if (
		!(element instanceof HTMLElement) ||
		!isPostRenderPhase(phase) ||
		!isBridgeCodeViewPostRenderContext(context)
	) {
		throw new Error('Expected Pierre public onPostRender element, instance, phase, and context.');
	}
	return { context, element, instance };
}

function isBridgeCodeViewPostRenderContext(
	value: unknown,
): value is Readonly<Record<string, unknown>> & { readonly item: CodeViewItem } {
	return isUnknownRecord(value) && isCodeViewItem(value['item']);
}

function isCodeViewItem(value: unknown): value is CodeViewItem {
	return (
		isUnknownRecord(value) &&
		typeof value['id'] === 'string' &&
		(value['type'] === 'diff' || value['type'] === 'file')
	);
}

function isPostRenderPhase(value: unknown): value is PostRenderPhase {
	return value === 'mount' || value === 'unmount' || value === 'update';
}

function isUnknownRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null;
}

function requireExactReviewPierreDiffItem(
	item: BridgeMainRenderPublicationItem,
): ExactReviewPierreDiffItem {
	if (!isExactReviewPierreDiffItem(item)) {
		throw new Error('Expected exact Review worker publication to be a public Pierre diff item.');
	}
	return item;
}

function requireCurrentReviewPierreDiffItem(
	codeView: CodeView,
	itemId: string,
): ExactReviewPierreDiffItem {
	const item = codeView.getItem(itemId);
	if (item === undefined || !isExactReviewPierreDiffItem(item)) {
		throw new Error(`Expected current Review item ${itemId} to carry Bridge publication metadata.`);
	}
	return item;
}

function isExactReviewPierreDiffItem(
	item: BridgeMainRenderPublicationItem | CodeViewItem,
): item is ExactReviewPierreDiffItem {
	if (item.type !== 'diff' || !('bridgeMetadata' in item)) return false;
	const language = item.fileDiff.lang;
	return language === undefined
		? !Object.hasOwn(item.fileDiff, 'lang')
		: bridgePierreOptionalHighlightLanguage(language) === language;
}

async function settleBridgeCodeViewState(
	isSettled: () => boolean,
	failureMessage: string,
): Promise<void> {
	for (let frameIndex = 0; frameIndex < 8; frameIndex += 1) {
		if (isSettled()) return;
		// oxlint-disable-next-line no-await-in-loop -- Each iteration is a bounded observable render boundary.
		await act(async (): Promise<void> => {
			await new Promise<void>((resolve): void => {
				setTimeout(resolve, 0);
			});
			await new Promise<void>((resolve): void => {
				requestAnimationFrame((): void => resolve());
			});
			await Promise.resolve();
		});
	}
	if (!isSettled()) throw new Error(failureMessage);
}
