import { afterEach, describe, expect, test, vi } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode renders the real app chrome.
import './bridge-app.css';
import type { BridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerRpcCommandInput } from '../core/comm-worker/bridge-worker-rpc-client.js';
import {
	actClick,
	actWait,
	installBridgeReadyHandshake,
	pollWithinActUntilEqual,
	pollWithinActUntilTruthy,
} from './bridge-app-browser-test-actions.js';
import { bridgeAppControlProbeSchema, type BridgeAppControlProbe } from './bridge-app-control.js';
import {
	bridgePanePositionFilePath,
	bridgePanePositionReviewItemId,
	installBridgePanePositionFixtures,
} from './bridge-app-pane-runtime-position-test-support.js';
import { BridgeAppProtocolRouter } from './bridge-app-protocol-router.js';

const paneRuntimeObservation = vi.hoisted(() => ({
	createCount: 0,
	disposeCount: 0,
	paneCommands: [] as BridgeWorkerRpcCommandInput[],
	paneMessageListeners: [] as Array<(message: BridgeWorkerServerToMainMessage) => void>,
	renderStores: new Map<'fileView' | 'review', BridgeMainRenderSnapshotStore>(),
	surfaceRequests: [] as Array<'fileView' | 'review'>,
}));

vi.mock('../core/comm-worker/bridge-pane-runtime.js', async (importOriginal) => {
	const actual =
		await importOriginal<typeof import('../core/comm-worker/bridge-pane-runtime.js')>();
	const { createBridgeMainRenderSnapshotStore } =
		await import('../core/comm-worker/bridge-main-render-snapshot-store.js');
	const { createBridgeMainRenderFulfillmentCoordinator } =
		await import('../core/comm-worker/bridge-main-render-fulfillment-coordinator.js');
	const { createBridgeWorkerRpcLifecycleStore } =
		await import('../core/comm-worker/bridge-worker-rpc-lifecycle-store.js');
	return {
		...actual,
		createBridgePaneRuntime: (): unknown => {
			paneRuntimeObservation.createCount += 1;
			const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
			const surfaceMessageListeners = new Map<
				'fileView' | 'review',
				Array<(message: BridgeWorkerServerToMainMessage) => void>
			>();
			let surfaceRequestSequence = 0;
			const surfaceClients = new Map(
				(['fileView', 'review'] as const).map((surface) => {
					const renderStore = createBridgeMainRenderSnapshotStore();
					const messageListeners: Array<(message: BridgeWorkerServerToMainMessage) => void> = [];
					const renderFulfillmentCoordinator = createBridgeMainRenderFulfillmentCoordinator({
						sendDisposition: (): void => {},
					});
					paneRuntimeObservation.renderStores.set(surface, renderStore);
					surfaceMessageListeners.set(surface, messageListeners);
					return [
						surface,
						{
							lifecycle: {
								getServerSnapshot: lifecycleStore.getServerSnapshot,
								getSnapshot: lifecycleStore.getSnapshot,
								subscribe: lifecycleStore.subscribe,
							},
							renderFulfillmentCoordinator,
							renderStore,
							send: (command: BridgeWorkerRpcCommandInput): string => {
								void command;
								surfaceRequestSequence += 1;
								return `surface-command-${surface}-${surfaceRequestSequence}`;
							},
							subscribeMessages: (
								listener: (message: BridgeWorkerServerToMainMessage) => void,
							): (() => void) => {
								messageListeners.push(listener);
								return (): void => {
									const listenerIndex = messageListeners.indexOf(listener);
									if (listenerIndex >= 0) messageListeners.splice(listenerIndex, 1);
								};
							},
							surface,
						},
					] as const;
				}),
			);
			return {
				dispose: (): void => {
					paneRuntimeObservation.disposeCount += 1;
					for (const surfaceClient of surfaceClients.values()) {
						surfaceClient.renderFulfillmentCoordinator.dispose();
						surfaceClient.renderStore.dispose();
					}
					lifecycleStore.dispose();
					surfaceMessageListeners.clear();
				},
				installNativeBootstrap: vi.fn(),
				installTelemetryProducer: vi.fn(),
				lifecycleStore,
				paneClient: {
					lifecycle: {
						getServerSnapshot: lifecycleStore.getServerSnapshot,
						getSnapshot: lifecycleStore.getSnapshot,
						subscribe: lifecycleStore.subscribe,
					},
					send: (command: BridgeWorkerRpcCommandInput): string => {
						paneRuntimeObservation.paneCommands.push(command);
						const requestId = `pane-command-${paneRuntimeObservation.paneCommands.length}`;
						for (const listener of paneRuntimeObservation.paneMessageListeners) {
							listener({
								direction: 'serverWorkerToMain',
								kind: 'health',
								requestId,
								status: 'ready',
								transferDescriptors: [],
								wireVersion: BRIDGE_WORKER_WIRE_VERSION,
							});
						}
						return requestId;
					},
					subscribeMessages: (
						listener: (message: BridgeWorkerServerToMainMessage) => void,
					): (() => void) => {
						paneRuntimeObservation.paneMessageListeners.push(listener);
						return (): void => {
							const listenerIndex = paneRuntimeObservation.paneMessageListeners.indexOf(listener);
							if (listenerIndex >= 0) {
								paneRuntimeObservation.paneMessageListeners.splice(listenerIndex, 1);
							}
						};
					},
				},
				setNativeBootstrapRequester: vi.fn(),
				surfaceClient: (surface: 'fileView' | 'review') => {
					paneRuntimeObservation.surfaceRequests.push(surface);
					return surfaceClients.get(surface);
				},
			};
		},
	};
});

describe('BridgeApp pane runtime hard cut', () => {
	afterEach(async () => {
		await actWait(async (): Promise<void> => {
			cleanup();
			await new Promise<void>((resolve) => window.setTimeout(resolve, 0));
		});
		vi.restoreAllMocks();
		paneRuntimeObservation.createCount = 0;
		paneRuntimeObservation.disposeCount = 0;
		paneRuntimeObservation.paneCommands = [];
		paneRuntimeObservation.paneMessageListeners = [];
		paneRuntimeObservation.renderStores.clear();
		paneRuntimeObservation.surfaceRequests = [];
		document.body.replaceChildren();
	});

	test('keeps one pane-owned runtime and stable surface clients across File to Review to File', async () => {
		// Arrange
		await actWait(async (): Promise<void> => {
			render(<BridgeAppProtocolRouter protocol="worktree-file" />);
			await new Promise<void>((resolve) => window.setTimeout(resolve, 0));
		});
		const appRoot = requireHTMLElement(document.querySelector('[data-testid="bridge-app-root"]'));
		expect(
			await pollWithinActUntilTruthy(() =>
				document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
			),
		).not.toBeNull();
		await actWait(
			() => new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve())),
		);

		// Act
		await actClick(requireActiveContextButton('review'));
		expect(
			await pollWithinActUntilEqual(
				() => appRoot.getAttribute('data-bridge-viewer-mode'),
				'review',
			),
		).toBe('review');
		await actWait(() => Promise.resolve());
		await actClick(requireActiveContextButton('file'));
		expect(
			await pollWithinActUntilEqual(() => appRoot.getAttribute('data-bridge-viewer-mode'), 'file'),
		).toBe('file');
		await actWait(
			() => new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve())),
		);

		// Assert
		expect(paneRuntimeObservation.createCount).toBe(1);
		expect(paneRuntimeObservation.surfaceRequests).toEqual(
			expect.arrayContaining(['fileView', 'review']),
		);
		expect(paneRuntimeObservation.disposeCount).toBe(0);
	});

	test('retains real File and Review tree and code positions across native surface requests', async () => {
		// Arrange
		const handshake = installBridgeReadyHandshake();
		await actWait(async (): Promise<void> => {
			render(
				<div style={{ height: '860px', overflow: 'hidden', width: '1,440px' }}>
					<BridgeAppProtocolRouter
						codeViewWorkerPoolEnabled={false}
						fileViewerProps={{ autoOpenInitialFile: true }}
						protocol="worktree-file"
					/>
				</div>,
			);
			await Promise.resolve();
		});
		const appRoot = requireHTMLElement(document.querySelector('[data-testid="bridge-app-root"]'));
		const retainedFileHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-file"]'),
		);
		const retainedReviewHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
		);
		await actWait(async (): Promise<void> => {
			installBridgePanePositionFixtures({
				fileRenderStore: requireRenderStore('fileView'),
				reviewRenderStore: requireRenderStore('review'),
			});
			await Promise.resolve();
		});

		// Act
		await requestNativeSurface({
			appRoot,
			nativeSelectionRequestId: 'native-selection-file-initial',
			selectionRevision: 1,
			surface: 'file',
		});
		const fileOwners = await waitForScrollableSurfaceOwners({
			host: retainedFileHost,
			surface: 'file',
		});
		expect(
			retainedFileHost
				.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')
				?.getAttribute('data-worktree-rendered-item-id'),
		).toBe('position-file-001');
		expect(
			retainedFileHost
				.querySelector('[data-testid="bridge-file-viewer-code-canvas"]')
				?.getAttribute('data-worktree-open-file-path'),
		).toBe(bridgePanePositionFilePath);
		const filePosition = await establishSemanticSurfacePosition(fileOwners);

		await requestNativeSurface({
			appRoot,
			nativeSelectionRequestId: 'native-selection-review',
			selectionRevision: 2,
			surface: 'review',
		});
		const reviewOwners = await waitForScrollableSurfaceOwners({
			host: retainedReviewHost,
			surface: 'review',
		});
		expect(
			Number(
				retainedReviewHost
					.querySelector('[data-testid="bridge-code-view-panel"]')
					?.getAttribute('data-code-view-item-count'),
			),
		).toBeGreaterThan(1);
		const reviewPosition = await establishSemanticSurfacePosition(reviewOwners);

		await requestNativeSurface({
			appRoot,
			nativeSelectionRequestId: 'native-selection-file',
			selectionRevision: 3,
			surface: 'file',
		});

		// Assert
		await assertSurfacePositionRetained({
			expected: filePosition,
			owners: fileOwners,
			surface: 'file',
		});

		// Act: reactivate Review once so its retained positions are proven while visible.
		await requestNativeSurface({
			appRoot,
			nativeSelectionRequestId: 'native-selection-review-return',
			selectionRevision: 4,
			surface: 'review',
		});

		// Assert
		await assertSurfacePositionRetained({
			expected: reviewPosition,
			owners: reviewOwners,
			surface: 'review',
		});
		await requestNativeSurface({
			appRoot,
			nativeSelectionRequestId: 'native-selection-file-final',
			selectionRevision: 5,
			surface: 'file',
		});
		await assertSurfacePositionRetained({
			expected: filePosition,
			owners: fileOwners,
			surface: 'file',
		});
		expect(document.querySelector('[data-testid="bridge-viewer-mode-host-file"]')).toBe(
			retainedFileHost,
		);
		expect(document.querySelector('[data-testid="bridge-viewer-mode-host-review"]')).toBe(
			retainedReviewHost,
		);
		expect(fileOwners.treeScrollOwner.isConnected).toBe(true);
		expect(fileOwners.codeScrollOwner.isConnected).toBe(true);
		expect(reviewOwners.treeScrollOwner.isConnected).toBe(true);
		expect(reviewOwners.codeScrollOwner.isConnected).toBe(true);
		expect(paneRuntimeObservation.createCount).toBe(1);
		expect(paneRuntimeObservation.disposeCount).toBe(0);
		handshake.dispose();
	});

	test('routes strict native page controls into the active Review and File owners', async () => {
		// Arrange
		await actWait(async (): Promise<void> => {
			render(
				<BridgeAppProtocolRouter
					codeViewWorkerPoolEnabled={false}
					fileViewerProps={{ autoOpenInitialFile: false }}
					protocol="review"
				/>,
			);
			await Promise.resolve();
		});
		await actWait(async (): Promise<void> => {
			installBridgePanePositionFixtures({
				fileRenderStore: requireRenderStore('fileView'),
				reviewRenderStore: requireRenderStore('review'),
			});
			await Promise.resolve();
		});
		const appRoot = requireHTMLElement(document.querySelector('[data-testid="bridge-app-root"]'));
		const reviewHost = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-mode-host-review"]'),
		);
		const reviewCodePanel = requireHTMLElement(
			await pollWithinActUntilTruthy(() =>
				reviewHost.querySelector('[data-testid="bridge-code-view-panel"]'),
			),
		);
		const initialCollapseButton = requireHTMLElement(
			await pollWithinActUntilTruthy(() =>
				reviewHost.querySelector(
					`[data-testid="bridge-code-view-header-collapse-button"][data-bridge-code-view-item-id="${bridgePanePositionReviewItemId}"]`,
				),
			),
		);
		const probes: Array<BridgeAppControlProbe | undefined> = [];

		// Act: drive Review through the exact page events emitted by Swift IPC.
		probes.push(
			await dispatchBridgePageControl({
				itemId: bridgePanePositionReviewItemId,
				method: 'bridge.diff.collapseFile',
			}),
		);
		expect.soft(initialCollapseButton.getAttribute('aria-expanded')).toBe('false');
		probes.push(
			await dispatchBridgePageControl({
				itemId: bridgePanePositionReviewItemId,
				method: 'bridge.diff.expandFile',
			}),
		);
		expect.soft(initialCollapseButton.getAttribute('aria-expanded')).toBe('true');
		const selectedReviewItemId = 'position-review-080';
		await dispatchBridgeReviewSelection(selectedReviewItemId);
		probes.push(
			await dispatchBridgePageControl({
				itemId: selectedReviewItemId,
				method: 'bridge.diff.scrollToFile',
			}),
		);
		probes.push(
			await dispatchBridgePageControl({
				method: 'bridge.fileTree.search',
				searchMode: { kind: 'text' },
				searchText: 'PositionReview080',
			}),
		);
		const reviewSearchValueAfterCommand = reviewSearchInputWithin(reviewHost)?.value;

		// Act: switch through production chrome, then route File reveal and search.
		await actClick(requireActiveContextButton('file'));
		expect(
			await pollWithinActUntilEqual(() => appRoot.getAttribute('data-bridge-viewer-mode'), 'file'),
		).toBe('file');
		probes.push(
			await dispatchBridgePageControl({
				method: 'bridge.fileTree.revealPath',
				path: bridgePanePositionFilePath,
			}),
		);
		probes.push(
			await dispatchBridgePageControl({
				method: 'bridge.fileTree.search',
				searchMode: { kind: 'text' },
				searchText: 'PositionFile080',
			}),
		);
		const fileShell = requireHTMLElement(
			document.querySelector('[data-testid="bridge-file-viewer-shell"]'),
		);
		const selectedFilePathBeforeInvalidCommand = fileShell.getAttribute(
			'data-selected-display-path',
		);
		const rejectedProbe = await dispatchBridgePageControl({
			method: 'bridge.fileTree.search',
			searchMode: { kind: 'text' },
			searchText: 42,
		});
		await actClick(requireActiveContextButton('review'));
		expect(
			await pollWithinActUntilEqual(
				() => appRoot.getAttribute('data-bridge-viewer-mode'),
				'review',
			),
		).toBe('review');
		const reviewSearchInputAfterReturn = reviewSearchInputWithin(reviewHost);
		const reviewSearchValueAfterReturn = reviewSearchInputAfterReturn?.value;
		await actWait(async (): Promise<void> => {
			reviewSearchInputAfterReturn?.dispatchEvent(
				new KeyboardEvent('keydown', { bubbles: true, composed: true, key: 'Escape' }),
			);
			await Promise.resolve();
		});
		await advanceAnimationFrame();
		const reviewSearchValueAfterExplicitClose = reviewSearchInputWithin(reviewHost)?.value;

		// Assert: probes and current production state move together; invalid input is inert.
		expect.soft(probes).toMatchObject([
			{
				itemId: bridgePanePositionReviewItemId,
				method: 'bridge.diff.collapseFile',
				status: 'accepted',
			},
			{
				itemId: bridgePanePositionReviewItemId,
				method: 'bridge.diff.expandFile',
				status: 'accepted',
			},
			{ itemId: selectedReviewItemId, method: 'bridge.diff.scrollToFile', status: 'accepted' },
			{ method: 'bridge.fileTree.search', status: 'accepted', treeSearchText: 'PositionReview080' },
			{
				method: 'bridge.fileTree.revealPath',
				path: bridgePanePositionFilePath,
				status: 'accepted',
			},
			{ method: 'bridge.fileTree.search', status: 'accepted', treeSearchText: 'PositionFile080' },
		]);
		expect.soft(reviewCodePanel.getAttribute('data-selected-item-id')).toBe(selectedReviewItemId);
		expect.soft(reviewSearchValueAfterCommand).toBe('positionreview080');
		expect.soft(reviewSearchValueAfterReturn).toBe('positionreview080');
		expect.soft(reviewSearchValueAfterExplicitClose).toBe('');
		expect
			.soft(fileShell.getAttribute('data-selected-display-path'))
			.toBe(bridgePanePositionFilePath);
		expect
			.soft(fileShell.getAttribute('data-worktree-open-file-path'))
			.toBe(bridgePanePositionFilePath);
		expect.soft(fileSearchInput()?.value).toBe('PositionFile080');
		expect.soft(rejectedProbe).toMatchObject({
			method: 'bridge.fileTree.search',
			status: 'rejected',
		});
		expect(fileShell.getAttribute('data-selected-display-path')).toBe(
			selectedFilePathBeforeInvalidCommand,
		);
	});
});

interface SurfacePositionOwners {
	readonly codeScrollOwner: HTMLElement;
	readonly treeScrollOwner: HTMLElement;
}

interface SurfacePositionSnapshot {
	readonly codeScrollTop: number;
	readonly treeScrollTop: number;
}

async function requestNativeSurface(props: {
	readonly appRoot: HTMLElement;
	readonly nativeSelectionRequestId: string;
	readonly selectionRevision: number;
	readonly surface: 'file' | 'review';
}): Promise<void> {
	await publishNativeSurfaceSelectionRequest(props);
	expect(
		await pollWithinActUntilEqual(
			() => props.appRoot.getAttribute('data-bridge-viewer-mode'),
			props.surface,
		),
	).toBe(props.surface);
	const receipt = await pollWithinActUntilTruthy(() =>
		activeViewerModeUpdateForNativeRequest(props.nativeSelectionRequestId),
	);
	expect(receipt).toMatchObject({
		command: 'activeViewerModeUpdate',
		update: {
			mode: props.surface,
			nativeSelectionRequestId: props.nativeSelectionRequestId,
		},
	});
}

function requireRenderStore(surface: 'fileView' | 'review'): BridgeMainRenderSnapshotStore {
	const renderStore = paneRuntimeObservation.renderStores.get(surface);
	if (renderStore === undefined) {
		throw new Error(`Expected the pane runtime ${surface} render store.`);
	}
	return renderStore;
}

async function waitForScrollableSurfaceOwners(props: {
	readonly host: HTMLElement;
	readonly surface: 'file' | 'review';
	readonly remainingFrames?: number;
}): Promise<SurfacePositionOwners> {
	const remainingFrames = props.remainingFrames ?? 180;
	const treeScrollOwner = treeScrollOwnerWithinHost(props.host);
	const codeScrollOwner = props.host.querySelector('.bridge-code-view-scroll-owner');
	if (
		treeScrollOwner instanceof HTMLElement &&
		codeScrollOwner instanceof HTMLElement &&
		treeScrollOwner.scrollHeight > treeScrollOwner.clientHeight &&
		codeScrollOwner.scrollHeight > codeScrollOwner.clientHeight
	) {
		return { codeScrollOwner, treeScrollOwner };
	}
	if (remainingFrames <= 0) {
		throw new Error(
			`Expected scrollable ${props.surface} owners; tree=${treeScrollOwner?.scrollHeight ?? 'missing'}/${treeScrollOwner?.clientHeight ?? 'missing'} code=${codeScrollOwner instanceof HTMLElement ? `${codeScrollOwner.scrollHeight}/${codeScrollOwner.clientHeight}` : 'missing'}.`,
		);
	}
	await advanceAnimationFrame();
	return await waitForScrollableSurfaceOwners({
		...props,
		remainingFrames: remainingFrames - 1,
	});
}

function treeScrollOwnerWithinHost(host: HTMLElement): HTMLElement | null {
	const treeContainer = host.querySelector('file-tree-container');
	const scrollOwner = treeContainer?.shadowRoot?.querySelector(
		'[data-file-tree-virtualized-scroll="true"]',
	);
	return scrollOwner instanceof HTMLElement ? scrollOwner : null;
}

async function establishSemanticSurfacePosition(
	owners: SurfacePositionOwners,
): Promise<SurfacePositionSnapshot> {
	await actWait(async (): Promise<void> => {
		setUserScrollPosition(owners.treeScrollOwner, 0.37);
		setUserScrollPosition(owners.codeScrollOwner, 0.43);
		await Promise.resolve();
	});
	await waitForStableNonzeroScrollPosition(owners.treeScrollOwner);
	await waitForStableNonzeroScrollPosition(owners.codeScrollOwner);
	return surfacePositionSnapshot(owners);
}

function setUserScrollPosition(scrollOwner: HTMLElement, progress: number): void {
	const maximumScrollTop = scrollOwner.scrollHeight - scrollOwner.clientHeight;
	const nextScrollTop = Math.max(1, Math.floor(maximumScrollTop * progress));
	scrollOwner.dispatchEvent(
		new WheelEvent('wheel', { bubbles: true, deltaY: nextScrollTop, view: window }),
	);
	scrollOwner.scrollTop = nextScrollTop;
	scrollOwner.dispatchEvent(new Event('scroll', { bubbles: true }));
}

async function waitForStableNonzeroScrollPosition(
	scrollOwner: HTMLElement,
	remainingFrames = 60,
	previousScrollTop: number | null = null,
): Promise<void> {
	const currentScrollTop = scrollOwner.scrollTop;
	if (currentScrollTop > 0 && previousScrollTop === currentScrollTop) return;
	if (remainingFrames <= 0) {
		throw new Error(`Expected a stable nonzero scroll position; observed ${currentScrollTop}.`);
	}
	await advanceAnimationFrame();
	await waitForStableNonzeroScrollPosition(scrollOwner, remainingFrames - 1, currentScrollTop);
}

async function assertSurfacePositionRetained(props: {
	readonly expected: SurfacePositionSnapshot;
	readonly owners: SurfacePositionOwners;
	readonly surface: 'file' | 'review';
}): Promise<void> {
	await waitForStableNonzeroScrollPosition(props.owners.treeScrollOwner);
	await waitForStableNonzeroScrollPosition(props.owners.codeScrollOwner);
	const actual = surfacePositionSnapshot(props.owners);
	expect(actual.treeScrollTop, `${props.surface} tree position`).toBeGreaterThan(0);
	expect(actual.codeScrollTop, `${props.surface} code position`).toBeGreaterThan(0);
	expect(
		Math.abs(actual.codeScrollTop - props.expected.codeScrollTop),
		`${props.surface} code pixel position ${JSON.stringify({ actual, expected: props.expected })}`,
	).toBeLessThanOrEqual(1);
	expect(
		Math.abs(actual.treeScrollTop - props.expected.treeScrollTop),
		`${props.surface} tree pixel position ${JSON.stringify({ actual, expected: props.expected })}`,
	).toBeLessThanOrEqual(1);
}

function surfacePositionSnapshot(owners: SurfacePositionOwners): SurfacePositionSnapshot {
	return {
		codeScrollTop: owners.codeScrollOwner.scrollTop,
		treeScrollTop: owners.treeScrollOwner.scrollTop,
	};
}

function advanceAnimationFrame(): Promise<void> {
	return actWait(
		() =>
			new Promise<void>((resolve): void => {
				requestAnimationFrame((): void => resolve());
			}),
	);
}

async function publishNativeSurfaceSelectionRequest(props: {
	readonly nativeSelectionRequestId: string;
	readonly selectionRevision: number;
	readonly surface: 'file' | 'review';
}): Promise<void> {
	const request = {
		direction: 'serverWorkerToMain',
		kind: 'nativeSurfaceSelectionRequest',
		metadataStreamId: 'metadata-stream-1',
		nativeSelectionRequestId: props.nativeSelectionRequestId,
		paneSessionId: 'pane-session-1',
		selectionRevision: props.selectionRevision,
		surface: props.surface,
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		workerInstanceId: 'worker-instance-1',
	} satisfies BridgeWorkerServerToMainMessage;
	await actWait(async (): Promise<void> => {
		for (const listener of paneRuntimeObservation.paneMessageListeners) listener(request);
		await Promise.resolve();
	});
}

function activeViewerModeUpdateForNativeRequest(
	nativeSelectionRequestId: string,
): BridgeWorkerRpcCommandInput | undefined {
	return paneRuntimeObservation.paneCommands.find(
		(command): boolean =>
			command.command === 'activeViewerModeUpdate' &&
			command.update.nativeSelectionRequestId === nativeSelectionRequestId,
	);
}

async function dispatchBridgeReviewSelection(itemId: string): Promise<void> {
	await actWait(async (): Promise<void> => {
		window.dispatchEvent(
			new CustomEvent('__bridge_select_review_item', {
				detail: { itemId },
			}),
		);
		await Promise.resolve();
	});
	await advanceAnimationFrame();
}

async function dispatchBridgePageControl(
	detail: unknown,
): Promise<BridgeAppControlProbe | undefined> {
	delete window.bridgeReviewControlProbe;
	await actWait(async (): Promise<void> => {
		window.dispatchEvent(new CustomEvent('__bridge_review_control', { detail }));
		await Promise.resolve();
	});
	await advanceAnimationFrame();
	const decodedProbe = bridgeAppControlProbeSchema.safeParse(window.bridgeReviewControlProbe);
	return decodedProbe.success ? decodedProbe.data : undefined;
}

function reviewSearchInputWithin(reviewHost: HTMLElement): HTMLInputElement | null {
	const treeContainer = reviewHost.querySelector('file-tree-container');
	const searchInput = treeContainer?.shadowRoot?.querySelector('[data-file-tree-search-input]');
	return searchInput instanceof HTMLInputElement ? searchInput : null;
}

function fileSearchInput(): HTMLInputElement | null {
	const searchInput = document.querySelector('[data-testid="worktree-file-search-input"]');
	return searchInput instanceof HTMLInputElement ? searchInput : null;
}

function requireActiveContextButton(mode: 'file' | 'review'): HTMLElement {
	return requireHTMLElement(
		document.querySelector(
			`[data-bridge-viewer-mode-active="true"] [data-testid="bridge-viewer-context-${mode}"]`,
		),
	);
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected an HTML element.');
	return element;
}
