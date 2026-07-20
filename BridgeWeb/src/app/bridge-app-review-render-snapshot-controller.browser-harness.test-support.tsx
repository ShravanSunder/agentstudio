import { useMemo, type ReactElement } from 'react';
import { vi } from 'vitest';

import {
	createBridgeMainRenderFulfillmentCoordinator,
	type BridgeMainRenderFulfillmentCoordinator,
} from '../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import { createBridgeMainRenderSnapshotStore } from '../core/comm-worker/bridge-main-render-snapshot-store.js';
import type { BridgePaneSurfaceClient } from '../core/comm-worker/bridge-pane-runtime.js';
import type {
	BridgeWorkerFileDisplayPatchEvent,
	BridgeWorkerReviewDisplayPatchEvent,
	BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerRpcCommandInput } from '../core/comm-worker/bridge-worker-rpc-client.js';
import {
	createBridgeWorkerRpcLifecycleStore,
	type BridgeWorkerRpcLifecycleStore,
} from '../core/comm-worker/bridge-worker-rpc-lifecycle-store.js';
import {
	bridgeFileViewerDisplayModelForSnapshot,
	type BridgeFileViewerDisplaySource,
} from '../file-viewer/bridge-file-viewer-display-model.js';
import { useBridgeFileViewerRenderSnapshotController } from '../file-viewer/bridge-file-viewer-render-snapshot-controller.js';
import { useBridgeFileViewerDisplaySourceReporter } from '../file-viewer/use-bridge-file-viewer-display-source-reporter.js';
import {
	hierarchicalReviewDisplayEvent,
	reviewDisplayItem,
} from './bridge-app-review-render-snapshot-controller.browser.test-support.js';
import {
	createBridgeReviewWorkerPierreCourier,
	useBridgeReviewRenderSnapshotController,
} from './bridge-app-review-render-snapshot-controller.js';

export { hierarchicalReviewDisplayEvent };

export function ReviewDirectDisplayProbe(props: {
	readonly reviewClient: BridgePaneSurfaceClient;
}): ReactElement {
	const pierreCourier = useMemo(() => createBridgeReviewWorkerPierreCourier(), []);
	const controller = useBridgeReviewRenderSnapshotController({
		pierreCourier,
		reviewClient: props.reviewClient,
	});
	return (
		<output
			data-review-item-order-length={controller.catalogSnapshot.itemOrderLength}
			data-review-later-row-path={controller.displayStore.getReviewTreeRowAtIndex(1)?.path ?? ''}
			data-review-source-status={controller.reviewSourceSlice?.status ?? 'absent'}
			data-review-tree-row-order-length={controller.catalogSnapshot.treeRowOrderLength}
			data-testid="review-direct-display-probe"
		/>
	);
}

export function ReviewIntakeLifecycleProbe(props: {
	readonly reviewClient: BridgePaneSurfaceClient;
}): ReactElement {
	const pierreCourier = useMemo(() => createBridgeReviewWorkerPierreCourier(), []);
	const controller = useBridgeReviewRenderSnapshotController({
		pierreCourier,
		reviewClient: props.reviewClient,
	});
	return (
		<button
			data-testid="review-intake-lifecycle-probe"
			onClick={(): void => {
				controller.setReviewCodeViewVisibleItemIds(['item-after-intake']);
				controller.emitSelectedReviewItemIntent('item-after-intake', 'user');
			}}
			type="button"
		>
			Exercise later Review intents
		</button>
	);
}

export function FileDisplaySourceProbe(props: {
	readonly onDisplaySourceChange: (source: BridgeFileViewerDisplaySource | null) => void;
}): ReactElement {
	const renderSnapshotController = useBridgeFileViewerRenderSnapshotController({ selection: null });
	const displayModel = useMemo(
		() => bridgeFileViewerDisplayModelForSnapshot(renderSnapshotController.fileDisplaySnapshot),
		[renderSnapshotController.fileDisplaySnapshot],
	);
	useBridgeFileViewerDisplaySourceReporter({
		onDisplaySourceChange: props.onDisplaySourceChange,
		source: displayModel.source,
	});
	return <output data-testid="file-display-source-probe" />;
}

export interface ReviewSurfaceHarness {
	readonly lifecycleStore: BridgeWorkerRpcLifecycleStore;
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
	readonly reviewClient: BridgePaneSurfaceClient;
	readonly sentCommands: BridgeWorkerRpcCommandInput[];
}

export interface FileSurfaceHarness {
	readonly fileViewClient: BridgePaneSurfaceClient;
	readonly publish: (message: BridgeWorkerServerToMainMessage) => void;
}

export function makeFileSurfaceHarness(): FileSurfaceHarness {
	const displayStore = createBridgeMainRenderSnapshotStore();
	const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
	let messageListener: ((message: BridgeWorkerServerToMainMessage) => void) | null = null;
	return {
		fileViewClient: {
			lifecycle: lifecycleStore,
			renderFulfillmentCoordinator: createTestRenderFulfillmentCoordinator(),
			renderStore: displayStore,
			send: vi.fn((): string => 'file-request-1'),
			subscribeMessages: (listener): (() => void) => {
				messageListener = listener;
				return (): void => {
					messageListener = null;
				};
			},
			surface: 'fileView',
		},
		publish: (message): void => {
			if (messageListener === null) throw new Error('Expected the File message listener.');
			messageListener(message);
		},
	};
}

export function makeReviewSurfaceHarness(): ReviewSurfaceHarness {
	const displayStore = createBridgeMainRenderSnapshotStore();
	const lifecycleStore = createBridgeWorkerRpcLifecycleStore();
	const sentCommands: BridgeWorkerRpcCommandInput[] = [];
	let messageListener: ((message: BridgeWorkerServerToMainMessage) => void) | null = null;
	return {
		lifecycleStore,
		publish: (message): void => {
			if (messageListener === null) throw new Error('Expected the Review message listener.');
			messageListener(message);
		},
		reviewClient: {
			lifecycle: lifecycleStore,
			renderFulfillmentCoordinator: createTestRenderFulfillmentCoordinator(),
			renderStore: displayStore,
			send: vi.fn((command): string => {
				const requestId = `review-request-${sentCommands.length + 1}`;
				lifecycleStore.startRequest({
					command: command.command,
					requestId,
					surface: 'review',
				});
				sentCommands.push(command);
				return requestId;
			}),
			subscribeMessages: (listener): (() => void) => {
				messageListener = listener;
				return (): void => {
					messageListener = null;
				};
			},
			surface: 'review',
		},
		sentCommands,
	};
}

export function reviewIntakeReadyCommands(
	commands: readonly BridgeWorkerRpcCommandInput[],
): readonly Extract<BridgeWorkerRpcCommandInput, { readonly command: 'reviewIntakeReady' }>[] {
	return commands.filter(
		(
			command,
		): command is Extract<BridgeWorkerRpcCommandInput, { readonly command: 'reviewIntakeReady' }> =>
			command.command === 'reviewIntakeReady',
	);
}

export function reviewIntakeReadyRequestIds(
	lifecycleStore: BridgeWorkerRpcLifecycleStore,
): string[] {
	return Object.values(lifecycleStore.getSnapshot().requestsById)
		.filter((request) => request.command === 'reviewIntakeReady')
		.map((request) => request.requestId);
}

function createTestRenderFulfillmentCoordinator(): BridgeMainRenderFulfillmentCoordinator {
	return createBridgeMainRenderFulfillmentCoordinator({
		cancelAnimationFrame: (_frameHandle): void => {},
		nowMilliseconds: (): number => 0,
		requestAnimationFrame: (_callback): number => {
			throw new Error('Review Browser fixture must not schedule paint validation.');
		},
		sendDisposition: (_receipt): void => {},
	});
}

export function fileDisplayEvent(props: {
	readonly projectionRevision: number;
	readonly sequence: number;
}): BridgeWorkerFileDisplayPatchEvent {
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'fileDisplayPatch',
		patches: [
			{
				operation: 'reset',
				payload: {
					sourceGeneration: 1,
					sourceId: 'source-1',
				},
				slice: 'fileTree',
			},
			{
				itemId: 'file-1',
				operation: 'upsert',
				payload: {
					availability: { kind: 'available' },
					displayPath: 'README.md',
					endsMidLine: false,
					endsWithNewline: true,
					extent: { kind: 'exactLineCount', lineCount: 1 },
					fileExtension: 'md',
					language: 'markdown',
					payloadByteCount: 6,
					payloadLineCount: 1,
					rowId: 'row-1',
					sizeBytes: 6,
					totalLineCount: 1,
					truncationKind: 'none',
				},
				slice: 'fileItem',
			},
		],
		projectionRevision: props.projectionRevision,
		sequence: props.sequence,
		surface: 'fileView',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

export function reviewDisplayEvent(props: {
	readonly itemId: string;
	readonly path: string;
	readonly projectionRevision: number;
	readonly sequence: number;
	readonly startIndex: number;
	readonly totalItemCount?: number;
}): BridgeWorkerReviewDisplayPatchEvent {
	const totalItemCount = props.totalItemCount ?? 2;
	return {
		direction: 'serverWorkerToMain',
		epoch: 1,
		kind: 'reviewDisplayPatch',
		patches: [
			{
				operation: 'upsert',
				payload: {
					metadataWindowIdentity: `review-window-${props.projectionRevision}`,
					reviewGeneration: 1,
					status: 'ready',
					summary: {
						additions: 1,
						deletions: 0,
						filesChanged: 2,
						hiddenFileCount: 0,
						visibleFileCount: 2,
					},
					totalItemCount,
					totalTreeRowCount: totalItemCount,
				},
				slice: 'reviewSource',
			},
			{
				operation: 'batch',
				payload: {
					items: [reviewDisplayItem(props.itemId, props.path)],
					operations: [],
					reset: props.startIndex === 0,
					startIndex: props.startIndex,
				},
				slice: 'reviewItem',
			},
			{
				operation: 'batch',
				payload: {
					reset: props.startIndex === 0,
					windows: [
						{
							rows: [
								{
									depth: 1,
									isDirectory: false,
									itemId: props.itemId,
									path: props.path,
									rowId: `row-${props.itemId}`,
								},
							],
							startIndex: props.startIndex,
						},
					],
				},
				slice: 'reviewTree',
			},
		],
		projectionRevision: props.projectionRevision,
		sequence: props.sequence,
		surface: 'review',
		transferDescriptors: [],
		wireVersion: 1,
	};
}

export function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected an HTML element.');
	return element;
}

export function requireDefined<TValue>(value: TValue | null | undefined, message: string): TValue {
	if (value === undefined || value === null) throw new Error(message);
	return value;
}

export async function settleRenderedReviewFrame(): Promise<void> {
	await Promise.resolve();
	await new Promise<void>((resolve) => {
		requestAnimationFrame((): void => resolve());
	});
	await Promise.resolve();
}
