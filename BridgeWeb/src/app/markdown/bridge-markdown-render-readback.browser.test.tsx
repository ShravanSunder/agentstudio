import { act, type ReactElement } from 'react';
import { afterEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load product Markdown styles.
import '../bridge-app.css';
import {
	createBridgeMainRenderFulfillmentCoordinator,
	type BridgeMainRenderFulfillmentCoordinator,
	type BridgeMainRenderPublicationItem,
} from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import { makeFilePublication } from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.test-support.js';
import type { BridgeWorkerFilePierreRenderJobEvent } from '../../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerRenderDispositionReceipt } from '../../core/comm-worker/bridge-worker-render-fulfillment.js';
import { BridgeMarkdownCanvas } from './bridge-markdown-canvas.js';
import type {
	BridgeMarkdownPresentationState,
	BridgeMarkdownRenderIntent,
} from './use-bridge-markdown-presentation.js';
import { useBridgeMarkdownSelectionRetirement } from './use-bridge-markdown-selection-retirement.js';

interface PendingAnimationFrame {
	readonly callback: FrameRequestCallback;
	readonly frameHandle: number;
}

describe('BridgeMarkdownCanvas render fulfillment Browser Mode', () => {
	afterEach(async () => {
		await cleanup();
		document.body.replaceChildren();
	});

	test('settles two sequential selected Markdown publications only after each sanitized article commits', async () => {
		const dispositions: BridgeWorkerRenderDispositionReceipt[] = [];
		const pendingAnimationFrames: PendingAnimationFrame[] = [];
		let nextFrameHandle = 1;
		const coordinator = createBridgeMainRenderFulfillmentCoordinator({
			cancelAnimationFrame: (frameHandle): void => {
				const frameIndex = pendingAnimationFrames.findIndex(
					(frame): boolean => frame.frameHandle === frameHandle,
				);
				if (frameIndex >= 0) pendingAnimationFrames.splice(frameIndex, 1);
			},
			nowMilliseconds: (): number => 1_000 + dispositions.length,
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

		const firstPublication = makeMarkdownPublication({
			itemId: 'readme-markdown',
			publicationSequence: 1,
		});
		const firstItem = firstPublication.job.payload.item;
		const firstIntent = markdownIntentForItem(firstItem, 1);
		stagePublication(coordinator, firstPublication, firstItem);

		const rendered = await render(
			<BridgeMarkdownCanvas
				isActive={true}
				presentationState={readyPresentation({
					htmlCandidate:
						'<h1>README committed</h1><script>globalThis.firstMarkdownRan = true</script>',
					intent: firstIntent,
					requestId: 'markdown-readback-first',
				})}
				renderFulfillment={{ coordinator, intent: firstIntent, selectedItem: firstItem }}
				retry={(): void => {}}
			/>,
		);

		const firstArticle = requireMarkdownArticle();
		expect(firstArticle.textContent).toContain('README committed');
		expect(firstArticle.querySelector('script')).toBeNull();
		expect(dispositionKinds(dispositions)).toEqual(['queued', 'applied']);
		await runNextAnimationFrame(pendingAnimationFrames);
		expect(dispositionKinds(dispositions)).toEqual(['queued', 'applied', 'painted']);

		const secondPublication = makeMarkdownPublication({
			itemId: 'diagram-markdown',
			publicationSequence: 2,
		});
		const secondItem = secondPublication.job.payload.item;
		const secondIntent = markdownIntentForItem(secondItem, 2);
		stagePublication(coordinator, secondPublication, secondItem);
		await rendered.rerender(
			<BridgeMarkdownCanvas
				isActive={true}
				presentationState={readyPresentation({
					htmlCandidate: '<h1>Diagram committed</h1><img src="https://example.com/tracker.png">',
					intent: secondIntent,
					requestId: 'markdown-readback-second',
				})}
				renderFulfillment={{ coordinator, intent: secondIntent, selectedItem: secondItem }}
				retry={(): void => {}}
			/>,
		);

		const secondArticle = requireMarkdownArticle();
		expect(secondArticle.textContent).toContain('Diagram committed');
		expect(secondArticle.querySelector('img')).toBeNull();
		expect(dispositionKinds(dispositions)).toEqual([
			'queued',
			'applied',
			'painted',
			'queued',
			'applied',
		]);
		await runNextAnimationFrame(pendingAnimationFrames);
		expect(dispositionKinds(dispositions)).toEqual([
			'queued',
			'applied',
			'painted',
			'queued',
			'applied',
			'painted',
		]);
	});

	test('rejects deferred paint when the committed Markdown identity changes before validation', async () => {
		const harness = createRenderFulfillmentHarness();
		const publication = makeMarkdownPublication({
			itemId: 'identity-markdown',
			publicationSequence: 3,
		});
		const item = publication.job.payload.item;
		const intent = markdownIntentForItem(item, 3);
		stagePublication(harness.coordinator, publication, item);
		const rendered = await render(
			<BridgeMarkdownCanvas
				isActive={true}
				presentationState={readyPresentation({
					htmlCandidate: '<h1>Accepted identity</h1>',
					intent,
					requestId: 'markdown-identity-accepted',
				})}
				renderFulfillment={{ coordinator: harness.coordinator, intent, selectedItem: item }}
				retry={(): void => {}}
			/>,
		);
		expect(dispositionKinds(harness.dispositions)).toEqual(['queued', 'applied']);

		await rendered.rerender(
			<BridgeMarkdownCanvas
				isActive={true}
				presentationState={readyPresentation({
					htmlCandidate: '<h1>Changed request identity</h1>',
					intent,
					requestId: 'markdown-identity-changed',
				})}
				renderFulfillment={{ coordinator: harness.coordinator, intent, selectedItem: item }}
				retry={(): void => {}}
			/>,
		);
		await runNextAnimationFrame(harness.pendingAnimationFrames);

		expect(dispositionKinds(harness.dispositions)).toEqual(['queued', 'applied', 'rejected']);
		expect(harness.dispositions.at(-1)).toMatchObject({ reason: 'stale_attempt' });
	});

	test('rejects deferred paint when the committed article disconnects into loading', async () => {
		const harness = createRenderFulfillmentHarness();
		const publication = makeMarkdownPublication({
			itemId: 'disconnected-markdown',
			publicationSequence: 4,
		});
		const item = publication.job.payload.item;
		const intent = markdownIntentForItem(item, 4);
		stagePublication(harness.coordinator, publication, item);
		const rendered = await render(
			<BridgeMarkdownCanvas
				isActive={true}
				presentationState={readyPresentation({
					htmlCandidate: '<h1>Connected document</h1>',
					intent,
					requestId: 'markdown-disconnect',
				})}
				renderFulfillment={{ coordinator: harness.coordinator, intent, selectedItem: item }}
				retry={(): void => {}}
			/>,
		);
		expect(dispositionKinds(harness.dispositions)).toEqual(['queued', 'applied']);

		await rendered.rerender(
			<BridgeMarkdownCanvas
				isActive={true}
				presentationState={{ status: 'loading', sourcePath: intent.sourcePath }}
				renderFulfillment={{ coordinator: harness.coordinator, intent, selectedItem: item }}
				retry={(): void => {}}
			/>,
		);
		expect(document.querySelector('[data-testid="bridge-markdown-canvas"]')).toBeNull();
		await runNextAnimationFrame(harness.pendingAnimationFrames);

		expect(dispositionKinds(harness.dispositions)).toEqual(['queued', 'applied', 'rejected']);
		expect(harness.dispositions.at(-1)).toMatchObject({ reason: 'stale_attempt' });
	});

	test('rejects deferred paint when the Markdown presentation fails before validation', async () => {
		const harness = createRenderFulfillmentHarness();
		const publication = makeMarkdownPublication({
			itemId: 'failed-markdown',
			publicationSequence: 5,
		});
		const item = publication.job.payload.item;
		const intent = markdownIntentForItem(item, 5);
		stagePublication(harness.coordinator, publication, item);
		const rendered = await render(
			<BridgeMarkdownCanvas
				isActive={true}
				presentationState={readyPresentation({
					htmlCandidate: '<h1>Initially committed</h1>',
					intent,
					requestId: 'markdown-before-failure',
				})}
				renderFulfillment={{ coordinator: harness.coordinator, intent, selectedItem: item }}
				retry={(): void => {}}
			/>,
		);
		expect(dispositionKinds(harness.dispositions)).toEqual(['queued', 'applied']);

		await rendered.rerender(
			<BridgeMarkdownCanvas
				isActive={true}
				presentationState={{ status: 'failed', sourcePath: intent.sourcePath }}
				renderFulfillment={{ coordinator: harness.coordinator, intent, selectedItem: item }}
				retry={(): void => {}}
			/>,
		);
		await runNextAnimationFrame(harness.pendingAnimationFrames);

		expect(dispositionKinds(harness.dispositions)).toEqual(['queued', 'applied', 'rejected']);
		expect(harness.dispositions.at(-1)).toMatchObject({ reason: 'stale_attempt' });
	});

	test('rejects an old deferred frame after the exact selected Markdown item changes', async () => {
		const harness = createRenderFulfillmentHarness();
		const firstPublication = makeMarkdownPublication({
			itemId: 'changed-selection-first',
			publicationSequence: 6,
		});
		const firstItem = firstPublication.job.payload.item;
		const firstIntent = markdownIntentForItem(firstItem, 6);
		stagePublication(harness.coordinator, firstPublication, firstItem);
		const rendered = await render(
			<BridgeMarkdownCanvas
				isActive={true}
				presentationState={readyPresentation({
					htmlCandidate: '<h1>First selection</h1>',
					intent: firstIntent,
					requestId: 'markdown-selection-first',
				})}
				renderFulfillment={{
					coordinator: harness.coordinator,
					intent: firstIntent,
					selectedItem: firstItem,
				}}
				retry={(): void => {}}
			/>,
		);

		const secondPublication = makeMarkdownPublication({
			itemId: 'changed-selection-second',
			publicationSequence: 7,
		});
		const secondItem = secondPublication.job.payload.item;
		const secondIntent = markdownIntentForItem(secondItem, 7);
		stagePublication(harness.coordinator, secondPublication, secondItem);
		await rendered.rerender(
			<BridgeMarkdownCanvas
				isActive={true}
				presentationState={readyPresentation({
					htmlCandidate: '<h1>Second selection</h1>',
					intent: secondIntent,
					requestId: 'markdown-selection-second',
				})}
				renderFulfillment={{
					coordinator: harness.coordinator,
					intent: secondIntent,
					selectedItem: secondItem,
				}}
				retry={(): void => {}}
			/>,
		);
		expect(dispositionKinds(harness.dispositions)).toEqual([
			'queued',
			'applied',
			'queued',
			'applied',
		]);

		await runNextAnimationFrame(harness.pendingAnimationFrames);
		await runNextAnimationFrame(harness.pendingAnimationFrames);

		expect(dispositionKinds(harness.dispositions)).toEqual([
			'queued',
			'applied',
			'queued',
			'applied',
			'rejected',
			'painted',
		]);
		expect(harness.dispositions.at(-2)).toMatchObject({ reason: 'stale_attempt' });
	});

	test('supersedes an abandoned selected Markdown publication through the existing coordinator', async () => {
		const harness = createRenderFulfillmentHarness();
		const publication = makeMarkdownPublication({
			itemId: 'abandoned-markdown',
			publicationSequence: 8,
		});
		const item = publication.job.payload.item;
		stagePublication(harness.coordinator, publication, item);
		const rendered = await render(
			<MarkdownSelectionRetirementHarness
				coordinator={harness.coordinator}
				displayedItemId={item.bridgeMetadata.itemId}
			/>,
		);
		expect(dispositionKinds(harness.dispositions)).toEqual(['queued']);

		await rendered.rerender(
			<MarkdownSelectionRetirementHarness
				coordinator={harness.coordinator}
				displayedItemId="next-markdown"
			/>,
		);

		expect(dispositionKinds(harness.dispositions)).toEqual(['queued', 'superseded']);
		expect(harness.dispositions.at(-1)).toMatchObject({ reason: 'stale_submission' });
	});
});

function MarkdownSelectionRetirementHarness(props: {
	readonly coordinator: BridgeMainRenderFulfillmentCoordinator;
	readonly displayedItemId: string | null;
}): ReactElement {
	useBridgeMarkdownSelectionRetirement(props);
	return <div />;
}

function createRenderFulfillmentHarness(): {
	readonly coordinator: BridgeMainRenderFulfillmentCoordinator;
	readonly dispositions: BridgeWorkerRenderDispositionReceipt[];
	readonly pendingAnimationFrames: PendingAnimationFrame[];
} {
	const dispositions: BridgeWorkerRenderDispositionReceipt[] = [];
	const pendingAnimationFrames: PendingAnimationFrame[] = [];
	let nextFrameHandle = 1;
	return {
		dispositions,
		pendingAnimationFrames,
		coordinator: createBridgeMainRenderFulfillmentCoordinator({
			cancelAnimationFrame: (frameHandle): void => {
				const frameIndex = pendingAnimationFrames.findIndex(
					(frame): boolean => frame.frameHandle === frameHandle,
				);
				if (frameIndex >= 0) pendingAnimationFrames.splice(frameIndex, 1);
			},
			nowMilliseconds: (): number => 2_000 + dispositions.length,
			requestAnimationFrame: (callback): number => {
				const frameHandle = nextFrameHandle;
				nextFrameHandle += 1;
				pendingAnimationFrames.push({ callback, frameHandle });
				return frameHandle;
			},
			sendDisposition: (receipt): void => {
				dispositions.push(receipt);
			},
		}),
	};
}

function stagePublication(
	coordinator: BridgeMainRenderFulfillmentCoordinator,
	publication: Parameters<BridgeMainRenderFulfillmentCoordinator['acceptPublication']>[0],
	item: BridgeMainRenderPublicationItem,
): void {
	expect(coordinator.acceptPublication(publication)).toBe('accepted');
	coordinator.bindPublicationItem({
		finalItem: item,
		publicationItem: item,
		residency: 'replaced',
	});
	coordinator.markPublicationQueued(publication);
}

function makeMarkdownPublication(props: {
	readonly itemId: string;
	readonly publicationSequence: number;
}): BridgeWorkerFilePierreRenderJobEvent {
	const publication = makeFilePublication(props);
	const publicationPayload = publication.job.payload;
	if (publicationPayload.kind !== 'codeViewFileItem') {
		throw new Error('Expected a File render payload fixture.');
	}
	const publicationItem = publicationPayload.item;
	if (publicationItem.type !== 'file') throw new Error('Expected a File publication fixture.');
	const sourcePath = `docs/${props.itemId}.md`;
	const markdownItem = {
		...publicationItem,
		bridgeMetadata: {
			...publicationItem.bridgeMetadata,
			displayPath: sourcePath,
		},
		file: {
			...publicationItem.file,
			contents: `# ${props.itemId}\n`,
			lang: 'markdown',
			name: sourcePath,
		},
	} satisfies typeof publicationItem;
	return {
		...publication,
		job: {
			...publication.job,
			payload: {
				...publicationPayload,
				item: markdownItem,
			},
		},
	};
}

function markdownIntentForItem(
	item: BridgeMainRenderPublicationItem,
	sourceGeneration: number,
): BridgeMarkdownRenderIntent {
	if (item.type !== 'file') throw new Error('Expected a File Markdown publication item.');
	return {
		sourceIdentity: {
			surface: 'file',
			sourceId: 'markdown-readback-source',
			sourceGeneration,
			fileId: item.bridgeMetadata.itemId,
			fileVersion: item.version ?? 0,
		},
		sourcePath: `docs/${item.bridgeMetadata.itemId}.md`,
		contentCacheKey: item.bridgeMetadata.cacheKey,
		contentHash: item.bridgeMetadata.cacheKey,
		markdownText: item.file.contents,
	};
}

function readyPresentation(props: {
	readonly htmlCandidate: string;
	readonly intent: BridgeMarkdownRenderIntent;
	readonly requestId: string;
}): Extract<BridgeMarkdownPresentationState, { readonly status: 'ready' }> {
	const identity = {
		requestId: props.requestId,
		sourceIdentity: props.intent.sourceIdentity,
		contentCacheKey: props.intent.contentCacheKey,
		contentHash: props.intent.contentHash,
		abortKey: 'bridge-markdown-file',
	};
	return {
		status: 'ready',
		sourcePath: props.intent.sourcePath,
		identity,
		renderResult: {
			schemaVersion: 1,
			method: 'markdown.render',
			ok: true,
			...identity,
			htmlCandidate: props.htmlCandidate,
			mermaidDiagrams: [],
			metrics: {
				durationMilliseconds: 1,
				inputBytes: props.intent.markdownText.length,
				outputBytes: props.htmlCandidate.length,
				mermaidDiagramCount: 0,
			},
		},
	};
}

function requireMarkdownArticle(): HTMLElement {
	const article = document.querySelector('[data-testid="bridge-markdown-canvas"]');
	if (!(article instanceof HTMLElement)) throw new Error('Expected a committed Markdown article.');
	return article;
}

async function runNextAnimationFrame(
	pendingAnimationFrames: PendingAnimationFrame[],
): Promise<void> {
	const nextFrame = pendingAnimationFrames.shift();
	if (nextFrame === undefined) throw new Error('Expected Markdown paint validation frame.');
	await act(async (): Promise<void> => {
		nextFrame.callback(performance.now());
		await Promise.resolve();
	});
}

function dispositionKinds(
	dispositions: readonly BridgeWorkerRenderDispositionReceipt[],
): readonly BridgeWorkerRenderDispositionReceipt['disposition'][] {
	return dispositions.map((receipt) => receipt.disposition);
}
