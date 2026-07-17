import { act, type ReactElement } from 'react';
import { render } from 'vitest-browser-react';

import { BridgeReviewViewerMode } from '../../app/bridge-app-review-viewer-mode.js';
import type { BridgeViewerNavigationCommand } from '../../app/bridge-viewer-navigation-models.js';
import { createBridgeMainRenderFulfillmentCoordinator } from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import { createBridgeMainRenderSnapshotStore } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from '../../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeWorkerReviewDisplayItem,
	BridgeWorkerReviewDisplayPatchEvent,
	BridgeWorkerServerToMainMessage,
} from '../../core/comm-worker/bridge-worker-contracts.js';
import { buildBridgeWorkerPierreRenderJob } from '../../core/comm-worker/bridge-worker-pierre-render-job.js';
import { makeBridgeWorkerRenderReceiptIdentity } from '../../core/comm-worker/bridge-worker-render-fulfillment.test-support.js';
import type { BridgeWorkerRpcCommandInput } from '../../core/comm-worker/bridge-worker-rpc-client.js';
import { createBridgeWorkerRpcLifecycleStore } from '../../core/comm-worker/bridge-worker-rpc-lifecycle-store.js';
import { bridgeContentDemandExecutionPolicy } from '../../core/demand/bridge-content-demand-policy.js';
import type {
	BridgeFileChangeKind,
	BridgeFileClass,
} from '../../foundation/review-package/bridge-review-package.js';
import type { BridgeTelemetrySample } from '../../foundation/telemetry/bridge-telemetry-event.js';
import type { BridgeTelemetryRecorder } from '../../foundation/telemetry/bridge-telemetry-recorder.js';
import { parseBridgeCodeViewDiffForBrowserTest } from '../code-view/bridge-code-view-browser-test-diff.js';
import { BridgeReviewProjectionWitnessRouter } from './bridge-review-projection-witness-router.js';
import { reviewWitnessTreeRows } from './bridge-viewer-browser-recovery-tree-fixture.js';
import { visibleTextIncludingOpenShadowRoots } from './bridge-viewer-browser-visible-text.js';
import { advanceBridgeReviewRecoveryWitnessFrames } from './bridge-viewer-browser.recovery-witness-scroll.test-support.js';

export {
	advanceBridgeReviewRecoveryWitnessFrames,
	scanBridgeReviewRecoveryWitnessDocument,
} from './bridge-viewer-browser.recovery-witness-scroll.test-support.js';
export type {
	BridgeReviewRecoveryMarkerConvergenceSample,
	BridgeReviewRecoveryScrollScan,
} from './bridge-viewer-browser.recovery-witness-scroll.test-support.js';

export interface BridgeReviewRecoveryWitnessFile {
	readonly changeKind?: BridgeFileChangeKind;
	readonly contentMarker: string;
	readonly fileClass?: BridgeFileClass;
	readonly itemId: string;
	readonly lineCount: number;
	readonly path: string;
}

export interface BridgeReviewRecoveryWitnessHarness {
	readonly codeScrollOwner: () => HTMLElement | null;
	readonly codeText: () => string;
	readonly files: readonly BridgeReviewRecoveryWitnessFile[];
	readonly paintedCodeViewItems: () => readonly BridgeReviewRecoveryPaintedItem[];
	readonly pierreSearchInput: () => HTMLInputElement | null;
	readonly pierreTreeHost: () => HTMLElement | null;
	readonly pierreTreePath: (path: string) => HTMLElement | null;
	readonly scrollTreePathIntoView: (path: string) => Promise<HTMLElement>;
	readonly publishCompleteContent: () => Promise<void>;
	readonly publishContentForItemIds: (itemIds: readonly string[]) => Promise<readonly string[]>;
	readonly publishDemandedContent: () => Promise<readonly string[]>;
	readonly publishDisplay: () => Promise<void>;
	readonly publishDisplayAppendFrom: (initialItemCount: number) => Promise<void>;
	readonly publishDisplayAtEpoch: (epoch: number) => Promise<void>;
	readonly publishDisplayAtPackageIdentity: (metadataWindowIdentity: string) => Promise<void>;
	readonly publishDisplayInTwoBatches: (initialItemCount: number) => Promise<void>;
	readonly publishFileContentForItemId: (itemId: string) => Promise<void>;
	readonly publishDisplayPrefix: (initialItemCount: number) => Promise<void>;
	readonly publishAuthoritativeDisplayAfterRetainedSelection: () => Promise<void>;
	readonly publishAuthoritativeDisplayWithImmediateLocalSelection: (
		selectedItemIndex: number,
	) => Promise<void>;
	readonly publishRetainedSelectedOnlyDisplay: (selectedItemIndex: number) => Promise<void>;
	readonly publishedContentItemIds: () => readonly string[];
	readonly renderedCodeViewItemIds: () => readonly string[];
	readonly renderResult: ReturnType<typeof render>;
	readonly markFileViewedCommandCount: () => number;
	readonly selectedItemCommandCount: () => number;
	readonly selectionScrollToPathSampleCount: () => number;
	readonly setActive: (isActive: boolean) => Promise<void>;
	readonly expandedTreePaths: () => readonly string[];
	readonly visibleCodeText: (scrollOwner: HTMLElement) => string;
	readonly viewportCommandVisibleItemIds: () => readonly (readonly string[])[];
}

export interface BridgeReviewRecoveryPaintedItem {
	readonly bottom: number;
	readonly itemId: string;
	readonly paintedLineCount: number;
	readonly text: string;
	readonly top: number;
}

interface ActiveReviewRecoveryWitnessHarness {
	readonly dispose: () => void;
}

const activeHarnesses = new Set<ActiveReviewRecoveryWitnessHarness>();

export function makeBridgeReviewRecoveryWitnessFiles(props: {
	readonly count: number;
	readonly lineCount: number;
	readonly markerPrefix: string;
}): readonly BridgeReviewRecoveryWitnessFile[] {
	return Array.from({ length: props.count }, (_, fileIndex): BridgeReviewRecoveryWitnessFile => {
		const ordinal = String(fileIndex + 1).padStart(3, '0');
		const groupOrdinal = String(Math.floor(fileIndex / 3) + 1).padStart(2, '0');
		return {
			contentMarker: `${props.markerPrefix}_CONTENT_${ordinal}`,
			itemId: `${props.markerPrefix.toLowerCase()}-item-${ordinal}`,
			lineCount: props.lineCount,
			path: `Sources/RecoveryGroup${groupOrdinal}/RecoveryFile${ordinal}.swift`,
		};
	});
}

export function renderBridgeReviewRecoveryWitness(
	files: readonly BridgeReviewRecoveryWitnessFile[],
	props: { readonly navigationCommand?: BridgeViewerNavigationCommand } = {},
): BridgeReviewRecoveryWitnessHarness {
	if (files.length === 0) throw new Error('Review recovery witness requires at least one file.');
	const renderStore = createBridgeMainRenderSnapshotStore();
	const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
	const sentCommands: BridgeWorkerRpcCommandInput[] = [];
	const telemetrySamples: BridgeTelemetrySample[] = [];
	const telemetryRecorder: BridgeTelemetryRecorder = {
		flush: (): boolean => true,
		isEnabled: (scope): boolean => scope === 'web',
		measure: (measureProps) => measureProps.operation(),
		record: (sample): void => {
			telemetrySamples.push(sample);
		},
	};
	const publishedContentItemIds = new Set<string>();
	let messageListener: ((message: BridgeWorkerServerToMainMessage) => void) | null = null;
	const reviewProjectionRouter = new BridgeReviewProjectionWitnessRouter();
	let isDisposed = false;
	const publishRawReviewDisplayEvent = (event: BridgeWorkerReviewDisplayPatchEvent): void => {
		reviewProjectionRouter.publishRaw(event);
	};
	const renderFulfillmentCoordinator = createBridgeMainRenderFulfillmentCoordinator({
		nowMilliseconds: (): number => 0,
		sendDisposition: (_receipt): void => {},
	});
	const reviewClient: BridgePaneSurfaceClient = {
		lifecycle: lifecycleStore,
		renderFulfillmentCoordinator,
		renderStore,
		send: (command): string => {
			sentCommands.push(command);
			if (command.command === 'reviewProjectionUpdate')
				reviewProjectionRouter.publishQuery(command);
			return `review-recovery-witness-request-${sentCommands.length}`;
		},
		subscribeMessages: (listener): (() => void) => {
			messageListener = listener;
			reviewProjectionRouter.setListener(listener);
			return (): void => {
				reviewProjectionRouter.clearListener(listener);
				if (messageListener === listener) messageListener = null;
			};
		},
		surface: 'review',
	};
	const telemetryRecorderRef = { current: telemetryRecorder };
	const renderWitnessRoot = (isActive: boolean): ReactElement => (
		<div data-testid="bridge-review-recovery-witness-root" style={{ height: 860, width: 1_440 }}>
			<BridgeReviewViewerMode
				codeViewWorkerPoolEnabled={false}
				isActive={isActive}
				{...(props.navigationCommand === undefined
					? {}
					: { navigationCommand: props.navigationCommand })}
				onActiveSourceChange={(): void => {}}
				reviewClient={reviewClient}
				telemetryRecorderRef={telemetryRecorderRef}
				viewerHeaderControls={<div />}
			/>
		</div>
	);
	const renderResult = render(renderWitnessRoot(true));
	const requireMessageListener = (): ((message: BridgeWorkerServerToMainMessage) => void) => {
		if (messageListener === null) {
			throw new Error(
				'Review recovery witness production surface did not subscribe to worker messages.',
			);
		}
		return messageListener;
	};
	const activeHarness: ActiveReviewRecoveryWitnessHarness = {
		dispose: (): void => {
			if (isDisposed) return;
			isDisposed = true;
			messageListener = null;
			renderFulfillmentCoordinator.dispose();
			renderStore.dispose();
			lifecycleStore.dispose();
			activeHarnesses.delete(activeHarness);
		},
	};
	activeHarnesses.add(activeHarness);
	return {
		codeScrollOwner: (): HTMLElement | null =>
			bridgeReviewRecoveryWitnessCodeScrollOwner(renderResult.container),
		codeText: (): string => bridgeReviewRecoveryWitnessCodeText(renderResult.container),
		files,
		paintedCodeViewItems: (): readonly BridgeReviewRecoveryPaintedItem[] =>
			bridgeReviewRecoveryWitnessPaintedItems(renderResult.container),
		pierreSearchInput: (): HTMLInputElement | null =>
			bridgeReviewRecoveryWitnessPierreSearchInput(renderResult.container),
		pierreTreeHost: (): HTMLElement | null =>
			bridgeReviewRecoveryWitnessPierreTreeHost(renderResult.container),
		pierreTreePath: (path: string): HTMLElement | null =>
			bridgeReviewRecoveryWitnessPierreTreePath(renderResult.container, path),
		scrollTreePathIntoView: async (path: string): Promise<HTMLElement> =>
			bridgeReviewRecoveryWitnessScrollTreePathIntoView(renderResult.container, path),
		publishCompleteContent: async (): Promise<void> => {
			await act(async (): Promise<void> => {
				const publish = requireMessageListener();
				for (const [fileIndex, file] of files.entries()) {
					for (const message of completeReviewContentMessages(file, fileIndex + 1)) {
						publish(message);
					}
					publishedContentItemIds.add(file.itemId);
				}
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(
				Math.ceil(files.length / bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame) + 4,
			);
		},
		publishContentForItemIds: async (itemIds: readonly string[]): Promise<readonly string[]> => {
			const requestedItemIds = new Set(itemIds);
			const requestedFiles = files.filter(
				(file): boolean =>
					requestedItemIds.has(file.itemId) && !publishedContentItemIds.has(file.itemId),
			);
			if (requestedFiles.length === 0) return [];
			await act(async (): Promise<void> => {
				const publish = requireMessageListener();
				for (const file of requestedFiles) {
					const fileIndex = files.indexOf(file);
					for (const message of completeReviewContentMessages(file, fileIndex + 1)) {
						publish(message);
					}
					publishedContentItemIds.add(file.itemId);
				}
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(
				Math.ceil(
					requestedFiles.length / bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
				) + 4,
			);
			return requestedFiles.map((file): string => file.itemId);
		},
		publishDemandedContent: async (): Promise<readonly string[]> => {
			const demandedItemIds = new Set<string>();
			for (const command of sentCommands) {
				if (command.command === 'select') demandedItemIds.add(command.selectedItemId);
				if (command.command === 'viewport') {
					for (const itemId of command.visibleItemIds) demandedItemIds.add(itemId);
				}
			}
			const demandedFiles = files.filter(
				(file): boolean =>
					demandedItemIds.has(file.itemId) && !publishedContentItemIds.has(file.itemId),
			);
			if (demandedFiles.length === 0) return [];
			await act(async (): Promise<void> => {
				const publish = requireMessageListener();
				for (const file of demandedFiles) {
					const fileIndex = files.indexOf(file);
					for (const message of completeReviewContentMessages(file, fileIndex + 1)) {
						publish(message);
					}
					publishedContentItemIds.add(file.itemId);
				}
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(
				Math.ceil(
					demandedFiles.length / bridgeContentDemandExecutionPolicy.applyPumpMaxUnitsPerFrame,
				) + 4,
			);
			return demandedFiles.map((file): string => file.itemId);
		},
		publishDisplay: async (): Promise<void> => {
			await act(async (): Promise<void> => {
				publishRawReviewDisplayEvent(reviewDisplayEvent(files));
				await import('../shell/review-viewer-shell.js');
				await Promise.resolve();
				await new Promise<void>((resolve): void => {
					requestAnimationFrame((): void => resolve());
				});
				await Promise.resolve();
			});
		},
		publishDisplayAppendFrom: async (initialItemCount: number): Promise<void> => {
			if (initialItemCount <= 0 || initialItemCount >= files.length) {
				throw new Error('Review display append requires a non-empty proper initial prefix.');
			}
			await act(async (): Promise<void> => {
				publishRawReviewDisplayEvent(reviewDisplayAppendEvent(files, initialItemCount));
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(4);
		},
		publishDisplayAtEpoch: async (epoch: number): Promise<void> => {
			await act(async (): Promise<void> => {
				publishRawReviewDisplayEvent(
					reviewDisplayEvent(files, {
						epoch,
						projectionRevision: epoch,
						sequence: epoch,
					}),
				);
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(4);
		},
		publishDisplayAtPackageIdentity: async (metadataWindowIdentity: string): Promise<void> => {
			await act(async (): Promise<void> => {
				publishRawReviewDisplayEvent(
					reviewDisplayEvent(files, {
						metadataWindowIdentity,
						projectionRevision: 2,
						sequence: 2,
					}),
				);
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(4);
		},
		publishDisplayInTwoBatches: async (initialItemCount: number): Promise<void> => {
			if (initialItemCount <= 0 || initialItemCount >= files.length) {
				throw new Error('Two-batch Review display requires a non-empty proper initial prefix.');
			}
			await act(async (): Promise<void> => {
				publishRawReviewDisplayEvent(reviewDisplayEvent(files.slice(0, initialItemCount)));
				await import('../shell/review-viewer-shell.js');
				await Promise.resolve();
				await new Promise<void>((resolve): void => {
					requestAnimationFrame((): void => resolve());
				});
				publishRawReviewDisplayEvent(reviewDisplayAppendEvent(files, initialItemCount));
				await Promise.resolve();
			});
		},
		publishFileContentForItemId: async (itemId: string): Promise<void> => {
			const file = files.find((candidate): boolean => candidate.itemId === itemId);
			if (file === undefined) {
				throw new Error(`Review file-content publication requires a fixture item: ${itemId}`);
			}
			await act(async (): Promise<void> => {
				const fileIndex = files.indexOf(file);
				const publish = requireMessageListener();
				for (const message of completeReviewFileContentMessages(file, fileIndex + 1)) {
					publish(message);
				}
				publishedContentItemIds.add(file.itemId);
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(5);
		},
		publishDisplayPrefix: async (initialItemCount: number): Promise<void> => {
			if (initialItemCount <= 0 || initialItemCount >= files.length) {
				throw new Error('Review display prefix requires a non-empty proper initial prefix.');
			}
			await act(async (): Promise<void> => {
				publishRawReviewDisplayEvent(reviewDisplayEvent(files.slice(0, initialItemCount)));
				await import('../shell/review-viewer-shell.js');
				await Promise.resolve();
				await new Promise<void>((resolve): void => {
					requestAnimationFrame((): void => resolve());
				});
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(4);
		},
		publishAuthoritativeDisplayAfterRetainedSelection: async (): Promise<void> => {
			await act(async (): Promise<void> => {
				publishRawReviewDisplayEvent(
					reviewDisplayEvent(files, { projectionRevision: 2, sequence: 2 }),
				);
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(4);
		},
		publishAuthoritativeDisplayWithImmediateLocalSelection: async (
			selectedItemIndex: number,
		): Promise<void> => {
			const selectedFile = files[selectedItemIndex];
			if (selectedFile === undefined) {
				throw new Error(
					`Immediate Review selection index is outside the fixture: ${selectedItemIndex}`,
				);
			}
			await act(async (): Promise<void> => {
				publishRawReviewDisplayEvent(
					reviewDisplayEvent(files, { projectionRevision: 2, sequence: 2 }),
				);
				renderStore.setLocalSelection({ selectedItemId: selectedFile.itemId, source: 'user' });
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(4);
		},
		publishRetainedSelectedOnlyDisplay: async (selectedItemIndex: number): Promise<void> => {
			const selectedFile = files[selectedItemIndex];
			if (selectedFile === undefined) {
				throw new Error(
					`Retained selected-only index is outside the fixture: ${selectedItemIndex}`,
				);
			}
			await act(async (): Promise<void> => {
				publishRawReviewDisplayEvent(reviewDisplayEvent([selectedFile]));
				await import('../shell/review-viewer-shell.js');
				await Promise.resolve();
				await new Promise<void>((resolve): void => {
					requestAnimationFrame((): void => resolve());
				});
				await Promise.resolve();
			});
		},
		publishedContentItemIds: (): readonly string[] => [...publishedContentItemIds],
		renderedCodeViewItemIds: (): readonly string[] =>
			queryBridgeReviewRecoveryWitnessOpenShadowRoots(
				renderResult.container,
				'[data-bridge-code-view-item-id]',
			)
				.map((element): string | null => element.getAttribute('data-bridge-code-view-item-id'))
				.filter((itemId): itemId is string => itemId !== null),
		renderResult,
		markFileViewedCommandCount: (): number =>
			sentCommands.filter((command) => command.command === 'markFileViewed').length,
		selectedItemCommandCount: (): number =>
			sentCommands.filter((command) => command.command === 'select').length,
		selectionScrollToPathSampleCount: (): number =>
			telemetrySamples.filter(
				(sample): boolean =>
					sample.name === 'performance.bridge.trees.scroll_to_path' &&
					sample.stringAttributes['agentstudio.bridge.scroll.reason'] === 'selected_path_effect',
			).length,
		setActive: async (isActive: boolean): Promise<void> => {
			await act(async (): Promise<void> => {
				renderResult.rerender(renderWitnessRoot(isActive));
				await Promise.resolve();
			});
			await advanceBridgeReviewRecoveryWitnessFrames(2);
		},
		expandedTreePaths: (): readonly string[] =>
			bridgeReviewRecoveryWitnessExpandedTreePaths(renderResult.container),
		visibleCodeText: (scrollOwner: HTMLElement): string =>
			bridgeReviewRecoveryWitnessVisibleCodeText(renderResult.container, scrollOwner),
		viewportCommandVisibleItemIds: (): readonly (readonly string[])[] =>
			sentCommands.flatMap((command): readonly (readonly string[])[] =>
				command.command === 'viewport' ? [[...command.visibleItemIds]] : [],
			),
	};
}

export function disposeBridgeReviewRecoveryWitnessHarnesses(): void {
	for (const harness of activeHarnesses) harness.dispose();
}

function bridgeReviewRecoveryWitnessCodeText(container: HTMLElement): string {
	const codePanel = container.querySelector('[data-testid="bridge-code-view-panel"]');
	return codePanel === null ? '' : textIncludingOpenShadowRoots(codePanel);
}

function bridgeReviewRecoveryWitnessVisibleCodeText(
	container: HTMLElement,
	scrollOwner: HTMLElement,
): string {
	const codePanel = container.querySelector('[data-testid="bridge-code-view-panel"]');
	if (codePanel === null) return '';
	const viewportBounds = scrollOwner.getBoundingClientRect();
	return visibleTextIncludingOpenShadowRoots(codePanel, viewportBounds);
}

function bridgeReviewRecoveryWitnessPaintedItems(
	container: HTMLElement,
): readonly BridgeReviewRecoveryPaintedItem[] {
	const codePanel = container.querySelector('[data-testid="bridge-code-view-panel"]');
	if (codePanel === null) return [];
	return queryBridgeReviewRecoveryWitnessOpenShadowRoots(codePanel, 'diffs-container').flatMap(
		(host): readonly BridgeReviewRecoveryPaintedItem[] => {
			const itemMarker = host.querySelector('[data-bridge-code-view-item-id]');
			const itemId = itemMarker?.getAttribute('data-bridge-code-view-item-id') ?? null;
			if (itemId === null) return [];
			const paintedLines =
				host.shadowRoot === null ? [] : [...host.shadowRoot.querySelectorAll('[data-line-index]')];
			const bounds = host.getBoundingClientRect();
			return [
				{
					bottom: bounds.bottom,
					itemId,
					paintedLineCount: paintedLines.length,
					text: paintedLines.map((line): string => line.textContent ?? '').join('\n'),
					top: bounds.top,
				},
			];
		},
	);
}

function bridgeReviewRecoveryWitnessPierreTreeHost(container: HTMLElement): HTMLElement | null {
	const treeHost = container.querySelector(
		'[data-testid="bridge-review-trees-panel"] file-tree-container',
	);
	return treeHost instanceof HTMLElement ? treeHost : null;
}

function bridgeReviewRecoveryWitnessPierreSearchInput(
	container: HTMLElement,
): HTMLInputElement | null {
	const searchInput = container.querySelector('[data-testid="bridge-review-search-input"]');
	return searchInput instanceof HTMLInputElement ? searchInput : null;
}

function bridgeReviewRecoveryWitnessPierreTreePath(
	container: HTMLElement,
	path: string,
): HTMLElement | null {
	const treeHost = bridgeReviewRecoveryWitnessPierreTreeHost(container);
	const candidatePaths = path.endsWith('/') ? [path] : [path, `${path}/`];
	const matchingRows: Element[] = [];
	for (const candidatePath of candidatePaths) {
		matchingRows.push(
			...(treeHost?.shadowRoot?.querySelectorAll(
				`[data-item-path="${CSS.escape(candidatePath)}"]`,
			) ?? []),
		);
	}
	const matchingRow =
		matchingRows.find((candidate): boolean => candidate.hasAttribute('aria-expanded')) ??
		matchingRows[0];
	return matchingRow instanceof HTMLElement ? matchingRow : null;
}

async function bridgeReviewRecoveryWitnessScrollTreePathIntoView(
	container: HTMLElement,
	path: string,
): Promise<HTMLElement> {
	const mountedRow = bridgeReviewRecoveryWitnessPierreTreePath(container, path);
	if (mountedRow !== null) return mountedRow;
	const treeHost = bridgeReviewRecoveryWitnessPierreTreeHost(container);
	const scrollOwner = treeHost?.shadowRoot?.querySelector(
		'[data-file-tree-virtualized-scroll="true"]',
	);
	if (!(scrollOwner instanceof HTMLElement)) {
		throw new Error(`Review tree scroll owner is missing for path: ${path}`);
	}
	const maximumScrollTop = Math.max(0, scrollOwner.scrollHeight - scrollOwner.clientHeight);
	const scrollStep = Math.max(1, scrollOwner.clientHeight * 0.75);
	const maximumStepCount = Math.ceil(maximumScrollTop / scrollStep) + 1;
	for (let stepIndex = 0; stepIndex <= maximumStepCount; stepIndex += 1) {
		const nextScrollTop = Math.min(maximumScrollTop, stepIndex * scrollStep);
		// oxlint-disable-next-line no-await-in-loop -- Each virtualized tree window is an observable frame boundary.
		await act(async (): Promise<void> => {
			scrollOwner.scrollTop = nextScrollTop;
			scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
			await Promise.resolve();
		});
		// oxlint-disable-next-line no-await-in-loop -- Pierre mounts the requested row after the scroll frame.
		await advanceBridgeReviewRecoveryWitnessFrames(1);
		const row = bridgeReviewRecoveryWitnessPierreTreePath(container, path);
		if (row !== null) return row;
	}
	throw new Error(`Review tree path did not enter the virtualized window: ${path}`);
}

function bridgeReviewRecoveryWitnessExpandedTreePaths(container: HTMLElement): readonly string[] {
	const treeHost = bridgeReviewRecoveryWitnessPierreTreeHost(container);
	return [
		...(treeHost?.shadowRoot?.querySelectorAll('[data-item-path][aria-expanded="true"]') ?? []),
	].flatMap((row): readonly string[] => {
		const path = row.getAttribute('data-item-path');
		return path === null ? [] : [path.replace(/\/$/u, '')];
	});
}

function bridgeReviewRecoveryWitnessCodeScrollOwner(container: HTMLElement): HTMLElement | null {
	const scrollOwner = container.querySelector('.bridge-code-view-scroll-owner');
	return scrollOwner instanceof HTMLElement ? scrollOwner : null;
}

function reviewDisplayEvent(
	files: readonly BridgeReviewRecoveryWitnessFile[],
	props: {
		readonly epoch?: number;
		readonly metadataWindowIdentity?: string;
		readonly projectionRevision?: number;
		readonly sequence?: number;
	} = {},
): BridgeWorkerReviewDisplayPatchEvent {
	const treeRows = reviewWitnessTreeRows(files);
	const projectionRevision = props.projectionRevision ?? 1;
	const metadataWindowIdentity =
		props.metadataWindowIdentity ?? `review-recovery-witness-window-r${projectionRevision}`;
	return {
		direction: 'serverWorkerToMain',
		epoch: props.epoch ?? 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					metadataWindowIdentity,
					status: 'ready',
					summary: {
						additions: files.length,
						deletions: files.length,
						filesChanged: files.length,
						hiddenFileCount: 0,
						visibleFileCount: files.length,
					},
					totalItemCount: files.length,
					totalTreeRowCount: treeRows.length,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: files.map(
						(file): BridgeWorkerReviewDisplayItem =>
							reviewDisplayItem(file, metadataWindowIdentity),
					),
					operations: [],
					reset: true,
					startIndex: 0,
				},
				slice: 'reviewItem',
			},
			{
				operation: 'batch',
				payload: {
					reset: true,
					windows: [{ rows: treeRows, startIndex: 0 }],
				},
				slice: 'reviewTree',
			},
		],
		projectionRevision,
		sequence: props.sequence ?? 1,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function queryBridgeReviewRecoveryWitnessOpenShadowRoots(
	root: Element | ShadowRoot,
	selector: string,
): readonly Element[] {
	const matches = [...root.querySelectorAll(selector)];
	for (const descendant of root.querySelectorAll('*')) {
		if (descendant.shadowRoot === null) continue;
		matches.push(
			...queryBridgeReviewRecoveryWitnessOpenShadowRoots(descendant.shadowRoot, selector),
		);
	}
	return matches;
}

function reviewDisplayAppendEvent(
	files: readonly BridgeReviewRecoveryWitnessFile[],
	initialItemCount: number,
): BridgeWorkerReviewDisplayPatchEvent {
	const previousTreeRowCount = reviewWitnessTreeRows(files.slice(0, initialItemCount)).length;
	const treeRows = reviewWitnessTreeRows(files);
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					metadataWindowIdentity: 'review-recovery-witness-window-r2',
					status: 'ready',
					summary: {
						additions: files.length,
						deletions: files.length,
						filesChanged: files.length,
						hiddenFileCount: 0,
						visibleFileCount: files.length,
					},
					totalItemCount: files.length,
					totalTreeRowCount: treeRows.length,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: files
						.slice(initialItemCount)
						.map((file): BridgeWorkerReviewDisplayItem => reviewDisplayItem(file)),
					operations: [],
					reset: false,
					startIndex: initialItemCount,
				},
				slice: 'reviewItem',
			},
			{
				operation: 'batch',
				payload: {
					reset: false,
					windows: [
						{
							rows: treeRows.slice(previousTreeRowCount),
							startIndex: previousTreeRowCount,
						},
					],
				},
				slice: 'reviewTree',
			},
		],
		projectionRevision: 2,
		sequence: 2,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

function reviewDisplayItem(
	file: BridgeReviewRecoveryWitnessFile,
	metadataWindowIdentity = 'review-recovery-witness-window-r2',
): BridgeWorkerReviewDisplayItem {
	const semanticDocumentRevision = `review-recovery-semantic:${file.itemId}:${file.contentMarker}`;
	return {
		contentFacts: [
			{
				contentDigest: {
					algorithm: 'review-recovery-fixture',
					authority: 'provisional',
					value: `base:${file.itemId}`,
				},
				role: 'base',
				semanticDocumentRevision,
			},
			{
				contentDigest: {
					algorithm: 'review-recovery-fixture',
					authority: 'provisional',
					value: `head:${file.itemId}:${file.contentMarker}`,
				},
				role: 'head',
				semanticDocumentRevision,
			},
		],
		extentFacts: [
			{ contentRole: 'base', itemId: file.itemId, lineCount: file.lineCount },
			{ contentRole: 'head', itemId: file.itemId, lineCount: file.lineCount },
		],
		metadata: {
			basePath: file.path,
			changeKind: file.changeKind ?? 'modified',
			contentDescriptorIdsByRole: {},
			contentHashesByRole: {},
			contentRoles: ['base', 'head'],
			extension: 'swift',
			fileClass: file.fileClass ?? 'source',
			headPath: file.path,
			isHiddenByDefault: false,
			itemId: file.itemId,
			language: 'swift',
			mimeTypes: ['text/x-swift'],
			provenance: { agentSessionIds: [], operationIds: [], promptIds: [] },
			reviewPriority: 'normal',
			reviewState: 'unreviewed',
		},
		metadataWindowIdentity,
	};
}

function completeReviewContentMessages(
	file: BridgeReviewRecoveryWitnessFile,
	publicationSequence: number,
): readonly BridgeWorkerServerToMainMessage[] {
	const baseContents = reviewWitnessFileContents(file, 'BASE');
	const headContents = reviewWitnessFileContents(file, file.contentMarker);
	const baseCacheKey = `review-recovery-base-${file.itemId}`;
	const headCacheKey = `review-recovery-head-${file.itemId}`;
	const contentCacheKey = `${baseCacheKey}|${headCacheKey}`;
	const job = buildBridgeWorkerPierreRenderJob({
		bridgeDemandRank: { lane: 'visible', priority: publicationSequence },
		budget: { className: 'visible', maxBytes: 512 * 1024, maxWindowLines: 400 },
		contentCacheKey,
		contentHash: `review-recovery-content-${file.itemId}`,
		itemId: file.itemId,
		language: 'swift',
		payload: {
			item: {
				bridgeMetadata: {
					cacheKey: contentCacheKey,
					contentRoles: ['base', 'head'],
					contentState: 'hydrated',
					displayPath: file.path,
					itemId: file.itemId,
					lineCount: file.lineCount * 2,
				},
				fileDiff: parseBridgeCodeViewDiffForBrowserTest(
					{ cacheKey: baseCacheKey, contents: baseContents, name: file.path },
					{ cacheKey: headCacheKey, contents: headContents, name: file.path },
				),
				id: file.itemId,
				type: 'diff',
				version: 1,
			},
			kind: 'codeViewDiffItem',
		},
		renderKind: 'reviewDiff',
		window: { endLine: file.lineCount, startLine: 1, totalLineCount: file.lineCount },
	});
	return [
		{
			direction: 'serverWorkerToMain',
			job,
			kind: 'reviewPierreRenderJob',
			publicationSequence,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: job.itemId,
				publicationSequence,
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
		},
		{
			direction: 'serverWorkerToMain',
			kind: 'reviewRenderPatch',
			patches: [
				{
					itemId: file.itemId,
					operation: 'upsert',
					payload: { contentCacheKey },
					slice: 'rowPaint',
				},
				{
					itemId: file.itemId,
					operation: 'upsert',
					payload: { state: 'ready' },
					slice: 'contentAvailability',
				},
			],
			publicationSequence,
			surface: 'review',
			transferDescriptors: [],
			wireVersion: 1,
			workerDerivationEpoch: 1,
		},
	];
}

function completeReviewFileContentMessages(
	file: BridgeReviewRecoveryWitnessFile,
	publicationSequence: number,
): readonly BridgeWorkerServerToMainMessage[] {
	const contents = reviewWitnessFileContents(file, file.contentMarker);
	const contentCacheKey = `review-recovery-file-${file.itemId}`;
	const job = buildBridgeWorkerPierreRenderJob({
		bridgeDemandRank: { lane: 'selected', priority: publicationSequence },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
		contentCacheKey,
		contentHash: `review-recovery-file-content-${file.itemId}`,
		itemId: file.itemId,
		language: 'swift',
		payload: {
			item: {
				bridgeMetadata: {
					cacheKey: contentCacheKey,
					contentRoles: ['head'],
					contentState: 'hydrated',
					displayPath: file.path,
					itemId: file.itemId,
					lineCount: file.lineCount,
				},
				file: { cacheKey: contentCacheKey, contents, lang: 'swift', name: file.path },
				id: file.itemId,
				type: 'file',
				version: 1,
			},
			kind: 'codeViewFileItem',
		},
		renderKind: 'fileText',
		window: { endLine: file.lineCount, startLine: 1, totalLineCount: file.lineCount },
	});
	return [
		{
			direction: 'serverWorkerToMain',
			job,
			kind: 'reviewPierreRenderJob',
			publicationSequence,
			renderReceiptIdentity: makeBridgeWorkerRenderReceiptIdentity({
				itemId: job.itemId,
				publicationSequence,
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
		},
		{
			direction: 'serverWorkerToMain',
			kind: 'reviewRenderPatch',
			patches: [
				{
					itemId: file.itemId,
					operation: 'upsert',
					payload: { contentCacheKey },
					slice: 'rowPaint',
				},
				{
					itemId: file.itemId,
					operation: 'upsert',
					payload: { state: 'ready' },
					slice: 'contentAvailability',
				},
			],
			publicationSequence,
			surface: 'review',
			transferDescriptors: [],
			wireVersion: 1,
			workerDerivationEpoch: 1,
		},
	];
}

function reviewWitnessFileContents(file: BridgeReviewRecoveryWitnessFile, marker: string): string {
	return Array.from(
		{ length: file.lineCount },
		(_, lineIndex): string =>
			`let recoveryWitness${String(lineIndex + 1).padStart(3, '0')} = "${marker}_LINE_${String(
				lineIndex + 1,
			).padStart(3, '0')}"`,
	).join('\n');
}

function textIncludingOpenShadowRoots(root: Element | ShadowRoot): string {
	const textFragments: string[] = [];
	const textWalker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
	let currentNode = textWalker.nextNode();
	while (currentNode !== null) {
		textFragments.push(currentNode.textContent ?? '');
		currentNode = textWalker.nextNode();
	}
	for (const descendant of root.querySelectorAll('*')) {
		if (descendant.shadowRoot !== null) {
			textFragments.push(textIncludingOpenShadowRoots(descendant.shadowRoot));
		}
	}
	return textFragments.join('\n');
}
