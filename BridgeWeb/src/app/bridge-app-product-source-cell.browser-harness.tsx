import { commands } from '@vitest/browser/context';
import { act } from 'react';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Source-cell Browser proof renders production app CSS.
import './bridge-app.css';
import type { BridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import {
	createBridgePaneRuntime,
	type BridgePaneRuntime,
} from '../core/comm-worker/bridge-pane-runtime.js';
import type { BridgeWorkerServerToMainMessage } from '../core/comm-worker/bridge-worker-contracts.js';
import { ensureBridgeCodeViewThemeResolved } from '../review-viewer/code-view/bridge-code-view-theme.js';
import { createBridgePierrePortableBlobWorkerFactory } from '../review-viewer/workers/pierre/bridge-pierre-dev-worker-factory.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import { createBridgeCommWorkerModuleWorker } from '../review-viewer/workers/shared-rpc/bridge-comm-worker-dev-factory.js';
import { actClick, installBridgeReadyHandshake } from './bridge-app-browser-test-actions.js';
import { parseBridgeAppDevFixtureOptions } from './bridge-app-dev-fixture.js';
import {
	installBridgeAppDevProductSessionHost,
	type BridgeAppDevProductSessionHost,
} from './bridge-app-dev-product-session-host.js';
import {
	bridgeProductSourceCellContentTraceSchema,
	bridgeProductSourceCellMetadataSchema,
	bridgeProductSourceCellOracleSchema,
	type BridgeProductSourceCellContentTraceEntry,
	type BridgeProductSourceCellMetadata,
	type BridgeProductSourceCellOracle,
	type BridgeProductSourceCellPaintCorrelation,
	type BridgeProductSourceCellPaintReport,
} from './bridge-app-product-source-cell-contract.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

const sourceCellMetadataRoute = '/__bridge-source-cell/metadata';
const sourceCellTraceRoute = '/__bridge-source-cell/trace';
const sourceCellFrameBudget = 600;

interface SourceCellPublication {
	readonly contentCacheKey: string;
	readonly itemId: string;
	readonly publicationSequence: number;
	readonly semanticItemId: string;
	readonly surface: 'file' | 'review';
	readonly workerDerivationEpoch: number;
}

export interface BridgeProductSourceCellJourney {
	readonly dispose: () => Promise<void>;
	readonly report: BridgeProductSourceCellPaintReport;
}

export async function runBridgeProductDeterministicSourceCellJourney(): Promise<BridgeProductSourceCellJourney> {
	let handshakeDisposer: (() => void) | null = null;
	let paneRuntime: BridgePaneRuntime | null = null;
	let productSessionHost: BridgeAppDevProductSessionHost | null = null;
	let pierreWorkerFactory: ReturnType<typeof createBridgePierrePortableBlobWorkerFactory> | null =
		null;
	let unmount: (() => void) | null = null;
	let disposed = false;
	const dispose = async (): Promise<void> => {
		if (disposed) return;
		disposed = true;
		await act(async (): Promise<void> => {
			unmount?.();
			unmount = null;
			handshakeDisposer?.();
			handshakeDisposer = null;
			productSessionHost?.dispose();
			productSessionHost = null;
			paneRuntime?.dispose();
			paneRuntime = null;
			terminateBridgePierreWorkerPoolSingletonForTest();
			pierreWorkerFactory?.revoke();
			pierreWorkerFactory = null;
			await Promise.resolve();
		});
	};
	try {
		await commands.bridgeInstallSourceCellNetworkProbe();
		const metadata = await fetchSourceCellMetadata();
		const oracle = await fetchSourceCellOracle(metadata);
		await ensureBridgeCodeViewThemeResolved();
		handshakeDisposer = installBridgeReadyHandshake({
			pushNonce: `source-cell-${metadata.runMarker}`,
		}).dispose;
		productSessionHost = installBridgeAppDevProductSessionHost();
		const portablePierreWorkerFactory = createBridgePierrePortableBlobWorkerFactory();
		pierreWorkerFactory = portablePierreWorkerFactory;
		const publicationByItemId = new Map<string, SourceCellPublication>();
		const runtimeDiagnostics: string[] = [];
		const navigationCommand = parseBridgeAppDevFixtureOptions(
			new URLSearchParams('fixture=worktree&viewer=review&workers=on'),
		).navigationCommand;
		let report: BridgeProductSourceCellPaintReport | null = null;
		let renderedContainer: HTMLElement | null = null;
		await act(async (): Promise<void> => {
			const rendered = render(
				<BridgeAppProtocolRouter
					codeViewWorkerFactory={portablePierreWorkerFactory.workerFactory}
					codeViewWorkerPoolEnabled
					fileViewerProps={{ autoOpenInitialFile: true }}
					navigationCommand={navigationCommand}
					paneRuntimeFactory={() => {
						if (paneRuntime === null) {
							paneRuntime = createBridgePaneRuntime({
								sessionProps: { workerFactory: createBridgeCommWorkerModuleWorker },
							});
							installPublicationObservers(paneRuntime, publicationByItemId, runtimeDiagnostics);
						}
						return paneRuntime;
					}}
				/>,
			);
			unmount = rendered.unmount;
			renderedContainer = rendered.container;
			await Promise.resolve();
		});
		if (renderedContainer === null) {
			throw new Error('Bridge source-cell app did not mount.');
		}
		const container = renderedContainer;
		const runtime = await waitForPaneRuntime(() => paneRuntime);
		const correlations = await captureReviewCorrelations({
			container,
			metadata,
			oracle,
			publicationByItemId,
			runtimeDiagnostics,
			runtime,
		});
		correlations.push(
			await captureFileCorrelation({
				container,
				metadata,
				oracle,
				publicationByItemId,
				runtimeDiagnostics,
				runtime,
			}),
		);
		const authorityPairs = new Set(
			correlations.map(
				(correlation): string =>
					`${correlation.paneSessionId ?? ''}\u0000${correlation.workerInstanceId ?? ''}`,
			),
		);
		if (authorityPairs.size !== 1) {
			throw new Error('Bridge source-cell journey crossed pane or worker authority.');
		}
		const authority = await waitForSourceCellAuthority();
		report = {
			...metadata,
			correlations: correlations.map(
				({ paneSessionId: _pane, workerInstanceId: _worker, ...rest }) => rest,
			),
			paneSessionId: authority.paneSessionId,
			workerInstanceId: authority.workerInstanceId,
		};
		if (report === null) {
			throw new Error('Bridge source-cell journey did not produce a paint report.');
		}
		return {
			dispose,
			report,
		};
	} catch (error: unknown) {
		await dispose();
		throw error;
	}
}

type CorrelationWithAuthority = BridgeProductSourceCellPaintCorrelation & {
	readonly paneSessionId: string;
	readonly workerInstanceId: string;
};

async function captureReviewCorrelations(props: {
	readonly container: HTMLElement;
	readonly metadata: BridgeProductSourceCellMetadata;
	readonly oracle: BridgeProductSourceCellOracle;
	readonly publicationByItemId: ReadonlyMap<string, SourceCellPublication>;
	readonly runtimeDiagnostics: readonly string[];
	readonly runtime: BridgePaneRuntime;
}): Promise<CorrelationWithAuthority[]> {
	const reviewStore = props.runtime.surfaceClient('review').renderStore;
	const itemIds = await waitForReviewItemIds(reviewStore, props.runtimeDiagnostics);
	const codePanel = await waitForElement(props.container, '[data-testid="bridge-code-view-panel"]');
	const targets = [
		{ itemId: itemIds[0] ?? '', position: 'early' as const },
		{
			itemId: itemIds[Math.floor(itemIds.length / 2)] ?? '',
			position: 'middle' as const,
		},
		{ itemId: itemIds.at(-1) ?? '', position: 'final' as const },
	];
	if (new Set(targets.map(({ itemId }) => itemId)).size !== 3) {
		throw new Error('Bridge source-cell Review fixture requires distinct traversal targets.');
	}
	const scrollOwner = await waitForElement(props.container, '.bridge-code-view-scroll-owner');
	const correlations: CorrelationWithAuthority[] = [];
	for (const target of targets) {
		// oxlint-disable-next-line no-await-in-loop -- Each product tree selection must reveal and paint before the next traversal target.
		await selectReviewTreeItem({
			container: props.container,
			itemId: target.itemId,
			store: reviewStore,
		});
		const oracleEntry = requireOracleEntry(props.oracle, 'review', target.itemId, 'head');
		// oxlint-disable-next-line no-await-in-loop -- Continuous traversal must paint each ordered source milestone before advancing.
		const readable = await scrollReviewUntilReadableItem({
			canaryText: oracleEntry.canaryText,
			itemId: target.itemId,
			root: codePanel,
			scrollOwner,
		});
		// oxlint-disable-next-line no-await-in-loop -- Server trace must be causally available for the painted item.
		const trace = await waitForContentTrace('review', target.itemId, 'head');
		// oxlint-disable-next-line no-await-in-loop -- Publication observation is independent from DOM polling.
		const publication = await waitForPublication(
			props.publicationByItemId,
			'review',
			target.itemId,
		);
		const selectedItemId = reviewStore.getSnapshot().selectionSlice.selectedItemId;
		if (selectedItemId === null) throw new Error('Bridge source-cell Review selection is missing.');
		correlations.push({
			...correlationFromObservations({
				metadata: props.metadata,
				oracleEntry,
				position: target.position,
				publication,
				readable,
				selectedItemId,
				selectionState: selectedItemId === target.itemId ? 'selected' : 'visible',
				trace,
			}),
			paneSessionId: trace.paneSessionId,
			workerInstanceId: trace.workerInstanceId,
		});
	}
	return correlations;
}

async function selectReviewTreeItem(props: {
	readonly container: HTMLElement;
	readonly itemId: string;
	readonly store: BridgeMainRenderSnapshotStore;
}): Promise<void> {
	const reviewItem = props.store.getReviewItemSnapshot(props.itemId);
	const path = reviewItem?.metadata.headPath ?? reviewItem?.metadata.basePath;
	if (path === null || path === undefined) {
		throw new Error(`Bridge source-cell Review item has no display path: ${props.itemId}.`);
	}
	const row = queryAllInOpenShadowRoots(props.container, '[data-item-path]').find(
		(candidate): boolean => candidate.getAttribute('data-item-path') === path,
	);
	if (!(row instanceof HTMLElement)) {
		throw new Error(`Bridge source-cell Review tree row is not mounted: ${path}.`);
	}
	await actClick(row);
	await waitForReviewSelection(props.store, props.itemId);
}

async function waitForReviewSelection(
	store: BridgeMainRenderSnapshotStore,
	itemId: string,
	attempt = 0,
): Promise<void> {
	if (store.getSnapshot().selectionSlice.selectedItemId === itemId) return;
	if (attempt >= sourceCellFrameBudget) {
		throw new Error(`Bridge source-cell Review selection did not commit: ${itemId}.`);
	}
	await advanceSourceCellFrames(1);
	await waitForReviewSelection(store, itemId, attempt + 1);
}

async function captureFileCorrelation(props: {
	readonly container: HTMLElement;
	readonly metadata: BridgeProductSourceCellMetadata;
	readonly oracle: BridgeProductSourceCellOracle;
	readonly publicationByItemId: ReadonlyMap<string, SourceCellPublication>;
	readonly runtimeDiagnostics: readonly string[];
	readonly runtime: BridgePaneRuntime;
}): Promise<CorrelationWithAuthority> {
	const fileContextButton = await waitForElement(
		props.container,
		'[data-testid="bridge-viewer-context-file"]',
	);
	await actClick(fileContextButton);
	const fileCanvas = await waitForElement(
		props.container,
		'[data-testid="bridge-file-viewer-code-canvas"]',
	);
	const fileStore = props.runtime.surfaceClient('fileView').renderStore;
	const selectedItemId = await waitForSelectedFileItemId(
		fileStore,
		props.container,
		props.runtimeDiagnostics,
		props.runtime,
	);
	await waitForPaintedFileTree({
		container: props.container,
		selectedItemId,
		store: fileStore,
	});
	const oracleEntry = requireOracleEntry(props.oracle, 'file', selectedItemId, 'file');
	const scrollOwner = await waitForElement(fileCanvas, '.bridge-code-view-scroll-owner');
	const readable = await waitForFileFinalReadableText({
		canaryText: oracleEntry.canaryText,
		fileCanvas,
		scrollOwner,
		selectedItemId,
	});
	const trace = await waitForContentTrace('file', selectedItemId, 'file');
	const publication = await waitForPublication(props.publicationByItemId, 'file', selectedItemId);
	return {
		...correlationFromObservations({
			metadata: props.metadata,
			oracleEntry,
			position: 'final',
			publication,
			readable,
			selectedItemId,
			selectionState: 'selected',
			trace,
		}),
		paneSessionId: trace.paneSessionId,
		workerInstanceId: trace.workerInstanceId,
	};
}

async function waitForPaintedFileTree(props: {
	readonly container: HTMLElement;
	readonly selectedItemId: string;
	readonly store: ReturnType<BridgePaneRuntime['surfaceClient']>['renderStore'];
	readonly attempt?: number;
}): Promise<void> {
	const snapshot = props.store.getSnapshot();
	const selectedDisplayPath = snapshot.fileItemById.get(props.selectedItemId)?.displayPath ?? null;
	const tree = props.container.querySelector('[data-testid="bridge-file-viewer-pierre-file-tree"]');
	const provenance = props.container.querySelector('[data-testid="worktree-file-provenance"]');
	const count = props.container.querySelector('[data-testid="worktree-file-filter-count"]');
	const countMatch = /^(\d+)\/(\d+)$/u.exec(count?.textContent?.trim() ?? '');
	const paintedSelectedRow =
		tree instanceof HTMLElement && selectedDisplayPath !== null
			? queryAllInOpenShadowRoots(tree, '[data-item-path]').some(
					(row): boolean => row.getAttribute('data-item-path') === selectedDisplayPath,
				)
			: false;
	if (
		paintedSelectedRow &&
		provenance?.textContent?.trim() !== 'Source pending' &&
		Number(countMatch?.[1] ?? 0) > 0 &&
		Number(countMatch?.[2] ?? 0) > 0
	) {
		return;
	}
	const attempt = props.attempt ?? 0;
	if (attempt >= sourceCellFrameBudget) {
		throw new Error(
			`Bridge source-cell File tree did not paint selected source; diagnostic=${JSON.stringify({
				count: count?.textContent?.trim() ?? null,
				provenance: provenance?.textContent?.trim() ?? null,
				selectedDisplayPath,
				treeRowPaths:
					tree instanceof HTMLElement
						? queryAllInOpenShadowRoots(tree, '[data-item-path]').map((row) =>
								row.getAttribute('data-item-path'),
							)
						: [],
			})}.`,
		);
	}
	await advanceSourceCellFrames(1);
	await waitForPaintedFileTree({ ...props, attempt: attempt + 1 });
}

function correlationFromObservations(props: {
	readonly metadata: BridgeProductSourceCellMetadata;
	readonly oracleEntry: BridgeProductSourceCellOracle['entries'][number];
	readonly position: BridgeProductSourceCellPaintCorrelation['position'];
	readonly publication: SourceCellPublication;
	readonly readable: { readonly itemId: string; readonly selector: string; readonly text: string };
	readonly selectedItemId: string;
	readonly selectionState: BridgeProductSourceCellPaintCorrelation['selectionState'];
	readonly trace: BridgeProductSourceCellContentTraceEntry;
}): BridgeProductSourceCellPaintCorrelation {
	if (
		props.publication.itemId !== props.trace.itemId ||
		props.publication.semanticItemId !== props.trace.itemId ||
		props.readable.itemId !== props.trace.itemId
	) {
		throw new Error('Bridge source-cell semantic item correlation is inconsistent.');
	}
	return {
		contentCacheKey: props.publication.contentCacheKey,
		contentRequestId: props.trace.contentRequestId,
		descriptorId: props.trace.descriptorId,
		disposition: 'painted',
		itemId: props.trace.itemId,
		observedSha256: props.trace.observedSha256,
		paintedPublicationSequence: props.publication.publicationSequence,
		position: props.position,
		readableDomItemId: props.readable.itemId,
		readableDomSelector: props.readable.selector,
		readableText: props.readable.text,
		requestId: props.trace.contentRequestId,
		role: props.trace.role,
		selectedItemId: props.selectedItemId,
		selectionState: props.selectionState,
		semanticItemId: props.publication.semanticItemId,
		sourceGeneration: props.trace.sourceGeneration,
		sourceIdentity: props.trace.sourceIdentity,
		surface: props.trace.surface,
		workerDerivationEpoch: props.publication.workerDerivationEpoch,
	};
}

function installPublicationObservers(
	runtime: BridgePaneRuntime,
	publicationByItemId: Map<string, SourceCellPublication>,
	runtimeDiagnostics: string[],
): void {
	for (const surface of ['fileView', 'review'] as const) {
		runtime.surfaceClient(surface).subscribeMessages((message): void => {
			if (message.kind === 'health') runtimeDiagnostics.push(JSON.stringify(message));
			if (surface === 'fileView' && message.kind === 'fileDisplayPatch') {
				runtimeDiagnostics.push(
					JSON.stringify({
						epoch: message.epoch,
						kind: message.kind,
						patches: message.patches.map((patch) => ({
							operation: patch.operation,
							slice: patch.slice,
						})),
						projectionRevision: message.projectionRevision,
						queryTransaction: message.queryTransaction ?? null,
						sequence: message.sequence,
					}),
				);
			}
			const publication = publicationForMessage(message);
			if (publication === null) return;
			publicationByItemId.set(`${publication.surface}:${publication.itemId}`, publication);
		});
	}
}

function publicationForMessage(
	message: BridgeWorkerServerToMainMessage,
): SourceCellPublication | null {
	if (message.kind !== 'filePierreRenderJob' && message.kind !== 'reviewPierreRenderJob') {
		return null;
	}
	const item = message.job.payload.item;
	return {
		contentCacheKey: item.bridgeMetadata.cacheKey,
		itemId: item.bridgeMetadata.itemId,
		publicationSequence: message.publicationSequence,
		semanticItemId: item.bridgeMetadata.itemId,
		surface: message.kind === 'filePierreRenderJob' ? 'file' : 'review',
		workerDerivationEpoch: message.workerDerivationEpoch,
	};
}

async function fetchSourceCellMetadata(): Promise<BridgeProductSourceCellMetadata> {
	const response = await fetch(sourceCellMetadataRoute, { cache: 'no-store' });
	if (!response.ok) throw new Error('Bridge source-cell metadata endpoint is unavailable.');
	return bridgeProductSourceCellMetadataSchema.parse(await response.json());
}

async function fetchSourceCellOracle(
	metadata: BridgeProductSourceCellMetadata,
): Promise<BridgeProductSourceCellOracle> {
	const response = await fetch(metadata.oracleUrl, { cache: 'no-store' });
	if (!response.ok) throw new Error('Bridge source-cell oracle endpoint is unavailable.');
	return bridgeProductSourceCellOracleSchema.parse(await response.json());
}

async function waitForContentTrace(
	surface: 'file' | 'review',
	itemId: string,
	role: string,
	attempt = 0,
): Promise<BridgeProductSourceCellContentTraceEntry> {
	const trace = await fetchSourceCellTraceWithinAct();
	const entry = trace.entries.find(
		(candidate): boolean =>
			candidate.surface === surface && candidate.itemId === itemId && candidate.role === role,
	);
	if (entry !== undefined) return entry;
	if (attempt >= sourceCellFrameBudget) {
		throw new Error(
			`Bridge source-cell content trace is missing for ${surface}:${itemId}:${role}.`,
		);
	}
	await advanceSourceCellFrames(1);
	return await waitForContentTrace(surface, itemId, role, attempt + 1);
}

async function waitForPublication(
	publications: ReadonlyMap<string, SourceCellPublication>,
	surface: 'file' | 'review',
	itemId: string,
	attempt = 0,
): Promise<SourceCellPublication> {
	const publication = publications.get(`${surface}:${itemId}`);
	if (publication !== undefined) return publication;
	if (attempt >= sourceCellFrameBudget) {
		throw new Error(`Bridge source-cell worker publication is missing for ${surface}:${itemId}.`);
	}
	await advanceSourceCellFrames(1);
	return await waitForPublication(publications, surface, itemId, attempt + 1);
}

async function waitForPaneRuntime(
	readRuntime: () => BridgePaneRuntime | null,
	attempt = 0,
): Promise<BridgePaneRuntime> {
	const runtime = readRuntime();
	if (runtime !== null) return runtime;
	if (attempt >= sourceCellFrameBudget)
		throw new Error('Bridge source-cell pane runtime is missing.');
	await advanceSourceCellFrames(1);
	return await waitForPaneRuntime(readRuntime, attempt + 1);
}

async function waitForReviewItemIds(
	store: BridgeMainRenderSnapshotStore,
	runtimeDiagnostics: readonly string[],
	attempt = 0,
): Promise<readonly string[]> {
	const itemIds = store
		.getSnapshot()
		.reviewItemIdsByIndex.filter((itemId): itemId is string => itemId !== null);
	if (itemIds.length >= 4) return itemIds;
	if (attempt >= sourceCellFrameBudget) {
		const sourceTrace = await fetchSourceCellTrace();
		const networkFailures = await commands.bridgeReadSourceCellNetworkFailures();
		throw new Error(
			`Bridge source-cell Review manifest is incomplete: ${itemIds.length}; diagnostics=${runtimeDiagnostics.join('|')}; requests=${sourceTrace.requests.join('|')}; networkFailures=${networkFailures.join('|')}.`,
		);
	}
	await advanceSourceCellFrames(1);
	return await waitForReviewItemIds(store, runtimeDiagnostics, attempt + 1);
}

async function fetchSourceCellTrace(): Promise<
	ReturnType<typeof bridgeProductSourceCellContentTraceSchema.parse>
> {
	const response = await fetch(sourceCellTraceRoute, { cache: 'no-store' });
	if (!response.ok) throw new Error('Bridge source-cell trace endpoint is unavailable.');
	return bridgeProductSourceCellContentTraceSchema.parse(await response.json());
}

function fetchSourceCellTraceWithinAct(): Promise<
	ReturnType<typeof bridgeProductSourceCellContentTraceSchema.parse>
> {
	return act(fetchSourceCellTrace);
}

async function waitForSelectedFileItemId(
	store: ReturnType<BridgePaneRuntime['surfaceClient']>['renderStore'],
	root: HTMLElement,
	runtimeDiagnostics: readonly string[],
	runtime: BridgePaneRuntime,
	attempt = 0,
): Promise<string> {
	const snapshot = store.getSnapshot();
	const selectedItemId = snapshot.selectionSlice.selectedItemId;
	if (
		selectedItemId !== null &&
		snapshot.contentAvailabilityById[selectedItemId]?.state === 'ready' &&
		snapshot.codeViewItemsById[selectedItemId] !== undefined
	) {
		return selectedItemId;
	}
	if (attempt >= sourceCellFrameBudget) {
		const sourceTrace = await fetchSourceCellTrace();
		throw new Error(
			`Bridge source-cell File item did not become selected and ready; diagnostic=${JSON.stringify(
				fileReadyDiagnostic(store, root, runtime),
			)}; runtime=${runtimeDiagnostics.join('|')}; requests=${sourceTrace.requests.join('|')}.`,
		);
	}
	await advanceSourceCellFrames(1);
	return await waitForSelectedFileItemId(store, root, runtimeDiagnostics, runtime, attempt + 1);
}

function fileReadyDiagnostic(
	store: ReturnType<BridgePaneRuntime['surfaceClient']>['renderStore'],
	root: HTMLElement,
	runtime: BridgePaneRuntime,
): unknown {
	const snapshot = store.getSnapshot();
	const fileModeHost = root.querySelector('[data-bridge-viewer-mode-host="file"]');
	return {
		availability: Object.fromEntries(
			Object.entries(snapshot.contentAvailabilityById).map(([itemId, value]) => [
				itemId,
				value.state,
			]),
		),
		codeViewItemIds: Object.keys(snapshot.codeViewItemsById),
		fileItemCount: snapshot.fileItemById.size,
		fileDisplayFreshness: snapshot.fileDisplayFreshness,
		fileModeActive: fileModeHost?.getAttribute('data-bridge-viewer-mode-active') ?? null,
		fileStatus: snapshot.fileStatusSlice,
		fileTreeRowCount: snapshot.fileTreeSlice.index.size,
		fileTreeSourceGeneration: snapshot.fileTreeSlice.sourceGeneration,
		fileTreeSourceId: snapshot.fileTreeSlice.sourceId,
		selectedItemId: snapshot.selectionSlice.selectedItemId,
		requests: runtime.lifecycleStore.getSnapshot().requestsById,
	};
}

async function waitForElement(
	root: ParentNode,
	selector: string,
	attempt = 0,
): Promise<HTMLElement> {
	const element = root.querySelector(selector);
	if (element instanceof HTMLElement) return element;
	if (attempt >= sourceCellFrameBudget) {
		throw new Error(
			`Bridge source-cell DOM element is missing: ${selector}; container=${sourceCellDomDiagnostic(root)}.`,
		);
	}
	await advanceSourceCellFrames(1);
	return await waitForElement(root, selector, attempt + 1);
}

function sourceCellDomDiagnostic(root: ParentNode): string {
	if (root instanceof Element) {
		const testIds = [...root.querySelectorAll('[data-testid]')]
			.map((element): string => element.getAttribute('data-testid') ?? '')
			.filter((testId): boolean => testId.length > 0);
		return JSON.stringify({ testIds, text: (root.textContent ?? '').slice(0, 2_000) });
	}
	return (root.textContent ?? '').slice(0, 2_000);
}

async function scrollReviewUntilReadableItem(props: {
	readonly canaryText: string;
	readonly itemId: string;
	readonly root: HTMLElement;
	readonly scrollOwner: HTMLElement;
	readonly attempt?: number;
}): Promise<{ readonly itemId: string; readonly selector: string; readonly text: string }> {
	const host = reviewHostForItem(props.root, props.itemId);
	const text = host === null ? '' : textIncludingOpenShadowRoots(host);
	if (host !== null && text.includes(props.canaryText)) {
		return {
			itemId: props.itemId,
			selector: `[data-bridge-code-view-item-id="${cssEscape(props.itemId)}"]`,
			text,
		};
	}
	const attempt = props.attempt ?? 0;
	if (attempt >= sourceCellFrameBudget) {
		throw new Error(
			`Bridge source-cell Review DOM is unreadable for ${props.itemId}; diagnostic=${JSON.stringify(
				reviewReadableDiagnostic(props.root),
			)}.`,
		);
	}
	const maximumScrollTop = Math.max(
		0,
		props.scrollOwner.scrollHeight - props.scrollOwner.clientHeight,
	);
	const nextScrollTop = Math.min(
		maximumScrollTop,
		props.scrollOwner.scrollTop + Math.max(1, Math.floor(props.scrollOwner.clientHeight * 0.5)),
	);
	await act(async (): Promise<void> => {
		props.scrollOwner.dispatchEvent(
			new WheelEvent('wheel', {
				bubbles: true,
				deltaY: Math.max(1, nextScrollTop - props.scrollOwner.scrollTop),
			}),
		);
		props.scrollOwner.scrollTop = nextScrollTop;
		props.scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
		await waitForAnimationFrames(4);
	});
	return await scrollReviewUntilReadableItem({ ...props, attempt: attempt + 1 });
}

async function waitForFileFinalReadableText(props: {
	readonly canaryText: string;
	readonly fileCanvas: HTMLElement;
	readonly scrollOwner: HTMLElement;
	readonly selectedItemId: string;
}): Promise<{ readonly itemId: string; readonly selector: string; readonly text: string }> {
	for (let attempt = 0; attempt < sourceCellFrameBudget; attempt += 1) {
		const text = textIncludingOpenShadowRoots(props.fileCanvas);
		if (text.includes(props.canaryText)) {
			return {
				itemId: props.selectedItemId,
				selector: `[data-testid="bridge-file-viewer-code-canvas"][data-worktree-rendered-item-id="${cssEscape(props.selectedItemId)}"]`,
				text,
			};
		}
		// oxlint-disable-next-line no-await-in-loop -- File virtualization must paint the final source before proof can continue.
		await act(async (): Promise<void> => {
			props.scrollOwner.scrollTop = Math.max(
				0,
				props.scrollOwner.scrollHeight - props.scrollOwner.clientHeight,
			);
			props.scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
			await waitForAnimationFrames(1);
		});
	}
	throw new Error('Bridge source-cell File final DOM source is unreadable.');
}

function reviewHostForItem(root: HTMLElement, itemId: string): Element | null {
	return (
		queryAllInOpenShadowRoots(root, 'diffs-container').find((host): boolean => {
			const marker = queryFirstInOpenShadowRoots(host, '[data-bridge-code-view-item-id]');
			return marker?.getAttribute('data-bridge-code-view-item-id') === itemId;
		}) ?? null
	);
}

function reviewReadableDiagnostic(root: HTMLElement): unknown {
	const scrollOwner = root.querySelector('.bridge-code-view-scroll-owner');
	return {
		hosts: queryAllInOpenShadowRoots(root, 'diffs-container').map((host) => {
			const bounds = host.getBoundingClientRect();
			const marker = queryFirstInOpenShadowRoots(host, '[data-bridge-code-view-item-id]');
			const contentState = queryFirstInOpenShadowRoots(
				host,
				'[data-bridge-code-view-content-state]',
			);
			const text = textIncludingOpenShadowRoots(host);
			return {
				bottom: bounds.bottom,
				contentState: contentState?.getAttribute('data-bridge-code-view-content-state') ?? null,
				itemId: marker?.getAttribute('data-bridge-code-view-item-id') ?? null,
				paintedLineCount: host.shadowRoot?.querySelectorAll('[data-line-index]').length ?? 0,
				textLength: text.length,
				textPrefix: text.slice(0, 160),
				top: bounds.top,
			};
		}),
		scroll:
			scrollOwner instanceof HTMLElement
				? {
						clientHeight: scrollOwner.clientHeight,
						scrollHeight: scrollOwner.scrollHeight,
						scrollTop: scrollOwner.scrollTop,
					}
				: null,
	};
}

function queryFirstInOpenShadowRoots(root: Element, selector: string): Element | null {
	const direct = root.querySelector(selector);
	if (direct !== null) return direct;
	for (const descendant of root.querySelectorAll('*')) {
		if (descendant.shadowRoot === null) continue;
		const nested = descendant.shadowRoot.querySelector(selector);
		if (nested !== null) return nested;
	}
	return root.shadowRoot?.querySelector(selector) ?? null;
}

function queryAllInOpenShadowRoots(root: Element | ShadowRoot, selector: string): Element[] {
	const matches = [...root.querySelectorAll(selector)];
	for (const descendant of root.querySelectorAll('*')) {
		if (descendant.shadowRoot === null) continue;
		matches.push(...queryAllInOpenShadowRoots(descendant.shadowRoot, selector));
	}
	return matches;
}

function textIncludingOpenShadowRoots(root: Element | ShadowRoot): string {
	const fragments = [root.textContent ?? ''];
	if (root instanceof Element && root.shadowRoot !== null) {
		fragments.push(textIncludingOpenShadowRoots(root.shadowRoot));
	}
	for (const descendant of root.querySelectorAll('*')) {
		if (descendant.shadowRoot !== null) {
			fragments.push(textIncludingOpenShadowRoots(descendant.shadowRoot));
		}
	}
	return fragments.join('\n');
}

function requireOracleEntry(
	oracle: BridgeProductSourceCellOracle,
	surface: 'file' | 'review',
	itemId: string,
	role: string,
): BridgeProductSourceCellOracle['entries'][number] {
	const entry = oracle.entries.find(
		(candidate): boolean =>
			candidate.surface === surface && candidate.itemId === itemId && candidate.role === role,
	);
	if (entry === undefined) {
		throw new Error(`Bridge source-cell oracle is missing ${surface}:${itemId}:${role}.`);
	}
	return entry;
}

async function waitForSourceCellAuthority(): Promise<{
	readonly paneSessionId: string;
	readonly workerInstanceId: string;
}> {
	const trace = await waitForAnyContentTrace();
	return { paneSessionId: trace.paneSessionId, workerInstanceId: trace.workerInstanceId };
}

async function waitForAnyContentTrace(
	attempt = 0,
): Promise<BridgeProductSourceCellContentTraceEntry> {
	const trace = await fetchSourceCellTraceWithinAct();
	const firstEntry = trace.entries[0];
	if (firstEntry !== undefined) return firstEntry;
	if (attempt >= sourceCellFrameBudget) throw new Error('Bridge source-cell authority is missing.');
	await advanceSourceCellFrames(1);
	return await waitForAnyContentTrace(attempt + 1);
}

async function advanceSourceCellFrames(count: number): Promise<void> {
	await act(async (): Promise<void> => {
		await waitForAnimationFrames(count);
	});
}

async function waitForAnimationFrames(count: number): Promise<void> {
	for (let frameIndex = 0; frameIndex < count; frameIndex += 1) {
		// oxlint-disable-next-line no-await-in-loop -- Browser proof advances exact animation-frame boundaries.
		await new Promise<void>((resolveFrame): number => requestAnimationFrame(() => resolveFrame()));
	}
}

function cssEscape(value: string): string {
	return globalThis.CSS?.escape(value) ?? value.replaceAll('"', '\\"');
}
