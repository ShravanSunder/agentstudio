import { act, useState, type ReactElement } from 'react';
import { describe, expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

import {
	registerBridgeCommWorkerRuntimePortProtocol,
	type BridgeCommWorkerPreparationDrain,
} from '../core/comm-worker/bridge-comm-worker-runtime-protocol.js';
import {
	activateBridgeCommWorkerFileViewerModeAndFlush,
	createRecordingBridgeCommWorkerPort,
	flushBridgeWorkerRuntimeContinuations,
	type FileMetadataDataFrame,
	type FileMetadataSubscription,
	type PostedBridgeWorkerRuntimeMessage,
} from '../core/comm-worker/bridge-comm-worker-runtime-protocol.test-support.js';
import { makeFileMetadataDataFrame } from '../core/comm-worker/bridge-comm-worker-runtime-protocol.test-support.js';
import type { BridgePaneCommWorkerDispatcher } from '../core/comm-worker/bridge-pane-comm-worker-session.js';
import {
	createBridgePaneRuntime,
	type BridgePaneSessionPort,
} from '../core/comm-worker/bridge-pane-runtime.js';
import { BridgeProductBoundedAsyncQueue } from '../core/comm-worker/bridge-product-async-queue.js';
import type {
	BridgeWorkerFilePierreRenderJobEvent,
	BridgeWorkerMainToServerMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import {
	drainFilePreparationUntilIdle,
	fileProductTestSource,
	fileViewProductTestBudget,
	makeDescriptorReadyEvent,
	makeFileProductTestTransport,
	makeTreeWindowEvent,
} from '../core/comm-worker/comm-runtime-protocol.file-product.test-support.js';
import type { BridgeFileViewerSelection } from './bridge-file-viewer-display-model.js';
import {
	BridgeFileViewerSurfaceClientProvider,
	type BridgeFileViewerRenderSnapshotController,
	useBridgeFileViewerRenderSnapshotController,
} from './bridge-file-viewer-render-snapshot-controller.js';

describe('Bridge File viewer code selection retirement', () => {
	test('publishes code B while code A still has an outstanding render receipt', async () => {
		// Arrange
		const harness = await createFileCodeSelectionHarness();
		try {
			await act(async (): Promise<void> => {
				harness.selectCodeFile('file-1');
				await drainFilePreparationUntilIdle(harness.scheduledDrains);
			});
			const publicationA = requireFilePublication(harness.postedMessages, 0);
			expect(publicationA.job.itemId).toBe('file-1');
			await expect
				.poll(() => hasQueuedRenderReceipt(harness.mainDispatchedMessages, 'file-1'))
				.toBe(true);
			expect(harness.controller.fileDisplaySnapshot.fileItemById.get('file-1')).toBeDefined();
			expect(harness.controller.selectedCodeViewItem?.bridgeMetadata.itemId).toBe('file-1');

			// Act: ordinary production Main selection advances to code B without ever painting A.
			await act(async (): Promise<void> => {
				harness.selectCodeFile('file-2');
				await drainFilePreparationUntilIdle(harness.scheduledDrains);
			});

			// Assert
			expect(filePublications(harness.postedMessages).map(({ job }) => job.itemId)).toEqual([
				'file-1',
				'file-2',
			]);
		} finally {
			await harness.close();
		}
	});

	test('rejects a withheld code A publication after selecting B, then publishes B', async () => {
		// Arrange
		const harness = await createFileCodeSelectionHarness({ holdFirstFilePublication: true });
		try {
			await act(async (): Promise<void> => {
				harness.selectCodeFile('file-1');
				await drainFilePreparationUntilIdle(harness.scheduledDrains);
			});
			expect(filePublications(harness.postedMessages).map(({ job }) => job.itemId)).toEqual([
				'file-1',
			]);

			// Act
			await act(async (): Promise<void> => {
				harness.selectCodeFile('file-2');
				await drainFilePreparationUntilIdle(harness.scheduledDrains);
				harness.releaseHeldFilePublication();
				await flushBridgeWorkerRuntimeContinuations();
			});
			await expect
				.poll(() =>
					hasTerminalRenderReceipt(harness.mainDispatchedMessages, {
						disposition: 'rejected',
						itemId: 'file-1',
					}),
				)
				.toBe(true);
			await act(async (): Promise<void> => {
				await drainFilePreparationUntilIdle(harness.scheduledDrains);
			});

			// Assert
			expect(filePublications(harness.postedMessages).map(({ job }) => job.itemId)).toEqual([
				'file-1',
				'file-2',
			]);
		} finally {
			await harness.close();
		}
	});

	test('supersedes queued code A when the File selection clears without publishing replacement work', async () => {
		// Arrange
		const harness = await createFileCodeSelectionHarness();
		try {
			await act(async (): Promise<void> => {
				harness.selectCodeFile('file-1');
				await drainFilePreparationUntilIdle(harness.scheduledDrains);
			});
			await expect
				.poll(() => hasQueuedRenderReceipt(harness.mainDispatchedMessages, 'file-1'))
				.toBe(true);

			// Act
			await act(async (): Promise<void> => {
				harness.clearSelection();
				await flushBridgeWorkerRuntimeContinuations();
			});
			await expect
				.poll(() =>
					hasTerminalRenderReceipt(harness.mainDispatchedMessages, {
						disposition: 'superseded',
						itemId: 'file-1',
					}),
				)
				.toBe(true);
			await act(async (): Promise<void> => {
				await drainFilePreparationUntilIdle(harness.scheduledDrains);
			});

			// Assert
			expect(filePublications(harness.postedMessages).map(({ job }) => job.itemId)).toEqual([
				'file-1',
			]);
		} finally {
			await harness.close();
		}
	});
});

interface FileCodeSelectionHarness {
	readonly close: () => Promise<void>;
	readonly clearSelection: () => void;
	readonly controller: BridgeFileViewerRenderSnapshotController;
	readonly mainDispatchedMessages: readonly BridgeWorkerMainToServerMessage[];
	readonly postedMessages: readonly PostedBridgeWorkerRuntimeMessage[];
	readonly releaseHeldFilePublication: () => void;
	readonly scheduledDrains: BridgeCommWorkerPreparationDrain[];
	readonly selectCodeFile: (fileId: string) => void;
}

async function createFileCodeSelectionHarness(
	options: { readonly holdFirstFilePublication?: boolean } = {},
): Promise<FileCodeSelectionHarness> {
	const metadataEvents = new BridgeProductBoundedAsyncQueue<FileMetadataDataFrame>(64);
	const scheduledDrains: BridgeCommWorkerPreparationDrain[] = [];
	const mainDispatchedMessages: BridgeWorkerMainToServerMessage[] = [];
	const subscription: FileMetadataSubscription = {
		cancel: async (): Promise<void> => {
			metadataEvents.close(true);
		},
		events: metadataEvents,
		subscriptionId: 'file-code-selection-retirement',
		subscriptionKind: 'file.metadata',
		update: async (): Promise<void> => {},
	};
	let publishWorkerMessages: Parameters<
		BridgePaneSessionPort['createDispatcher']
	>[0]['publishWorkerMessages'] = discardWorkerMessages;
	let heldFilePublication: BridgeWorkerFilePierreRenderJobEvent | null = null;
	const workerPort = createRecordingBridgeCommWorkerPort({
		beforePostMessage: (message): void => {
			if (
				options.holdFirstFilePublication === true &&
				message.kind === 'filePierreRenderJob' &&
				heldFilePublication === null
			) {
				heldFilePublication = message;
				return;
			}
			publishWorkerMessages([message]);
		},
	});
	registerBridgeCommWorkerRuntimePortProtocol(workerPort.dispatch.port, {
		bridgeDemandRank: { lane: 'selected', priority: 0 },
		budget: { className: 'interactive', maxBytes: 512 * 1024, maxWindowLines: 400 },
		fileViewBudget: fileViewProductTestBudget,
		productTransport: makeFileProductTestTransport({
			onDiscoverSource: (): void => {},
			onOpenDescriptor: (): void => {},
			subscription,
		}),
		schedulePreparationDrain: (drain): void => {
			scheduledDrains.push(drain);
		},
	});
	const paneRuntime = createBridgePaneRuntime({
		sessionFactory: (): BridgePaneSessionPort => ({
			createDispatcher: (props): BridgePaneCommWorkerDispatcher => {
				publishWorkerMessages = props.publishWorkerMessages;
				return {
					dispatch: (message): void => {
						mainDispatchedMessages.push(message);
						workerPort.dispatch.message(message);
					},
					dispose: (): void => {},
				};
			},
			dispose: (): void => {},
			installNativeBootstrap: (): void => {},
		}),
	});
	await activateBridgeCommWorkerFileViewerModeAndFlush(
		workerPort.dispatch,
		'code-selection-retirement',
	);
	for (const event of fileMetadataEventsForTwoCodeFiles()) {
		metadataEvents.push(makeFileMetadataDataFrame(event));
	}
	await flushBridgeWorkerRuntimeContinuations();

	const controllerProbe: FileSelectionControllerProbe = {
		clearSelection: null,
		current: null,
		selectCodeFile: null,
	};
	const rendered = await render(
		<BridgeFileViewerSurfaceClientProvider surfaceClient={paneRuntime.surfaceClient('fileView')}>
			<FileSelectionControllerProbe controllerProbe={controllerProbe} />
		</BridgeFileViewerSurfaceClientProvider>,
	);
	if (controllerProbe.selectCodeFile === null) {
		throw new Error('Expected the production File selection driver.');
	}
	return {
		close: async (): Promise<void> => {
			await rendered.unmount();
			metadataEvents.close(true);
			paneRuntime.dispose();
		},
		clearSelection: (): void => {
			const clearCurrentSelection = controllerProbe.clearSelection;
			if (clearCurrentSelection === null) {
				throw new Error('Expected the mounted production File selection clear driver.');
			}
			clearCurrentSelection();
		},
		get controller(): BridgeFileViewerRenderSnapshotController {
			const controller = controllerProbe.current;
			if (controller === null) {
				throw new Error('Expected the mounted production File selection controller.');
			}
			return controller;
		},
		mainDispatchedMessages,
		postedMessages: workerPort.postedMessages,
		releaseHeldFilePublication: (): void => {
			if (heldFilePublication === null) {
				throw new Error('Expected one withheld File publication.');
			}
			const publication = heldFilePublication;
			heldFilePublication = null;
			publishWorkerMessages([publication]);
		},
		scheduledDrains,
		selectCodeFile: (fileId): void => {
			const selectCurrentCodeFile = controllerProbe.selectCodeFile;
			if (selectCurrentCodeFile === null) {
				throw new Error('Expected the mounted production File selection driver.');
			}
			selectCurrentCodeFile(fileId);
		},
	};
}

interface FileSelectionControllerProbe {
	clearSelection: (() => void) | null;
	current: BridgeFileViewerRenderSnapshotController | null;
	selectCodeFile: ((fileId: string) => void) | null;
}

function FileSelectionControllerProbe(props: {
	readonly controllerProbe: FileSelectionControllerProbe;
}): ReactElement {
	const [selection, setSelection] = useState<BridgeFileViewerSelection | null>(null);
	const controller = useBridgeFileViewerRenderSnapshotController({ selection });
	props.controllerProbe.current = controller;
	props.controllerProbe.clearSelection = (): void => {
		setSelection(null);
		controller.clearSelectedFileViewContent();
	};
	props.controllerProbe.selectCodeFile = (fileId): void => {
		setSelection({
			fileId,
			path: fileId === 'file-1' ? 'Sources/File.swift' : 'Sources/SecondFile.swift',
		});
		controller.dispatchSelectedFileViewContentRequest({ fileId, selectedSource: 'user' });
	};
	return <div data-selected-file-id={selection?.fileId ?? 'none'} />;
}

function fileMetadataEventsForTwoCodeFiles(): readonly Parameters<
	typeof makeFileMetadataDataFrame
>[0][] {
	const treeWindow = makeTreeWindowEvent();
	const descriptorReady = makeDescriptorReadyEvent();
	if (
		treeWindow.eventKind !== 'file.treeWindow' ||
		descriptorReady.eventKind !== 'file.descriptorReady' ||
		descriptorReady.availability.availabilityKind !== 'available'
	) {
		throw new Error('Expected available production File metadata fixtures.');
	}
	const firstRow = treeWindow.rows[0];
	if (firstRow === undefined) throw new Error('Expected the first production File row fixture.');
	const secondRow = {
		...firstRow,
		fileId: 'file-2',
		name: 'SecondFile.swift',
		path: 'Sources/SecondFile.swift',
		rowId: 'row-file-2',
	};
	const secondDescriptor = {
		...descriptorReady,
		availability: {
			...descriptorReady.availability,
			contentDescriptor: {
				...descriptorReady.availability.contentDescriptor,
				descriptorId: 'descriptor-file-2',
				fileId: 'file-2',
			},
		},
		fileId: 'file-2',
		path: 'Sources/SecondFile.swift',
		rowId: 'row-file-2',
	};
	return [
		{ eventKind: 'file.sourceAccepted', source: fileProductTestSource },
		{ ...treeWindow, rows: [firstRow, secondRow], totalRowCount: 2 },
		descriptorReady,
		secondDescriptor,
	];
}

function discardWorkerMessages(): void {}

function hasQueuedRenderReceipt(
	messages: readonly BridgeWorkerMainToServerMessage[],
	itemId: string,
): boolean {
	return messages.some(
		(message): boolean =>
			message.command === 'renderDisposition' &&
			message.receipts.some(
				(receipt): boolean => receipt.itemId === itemId && receipt.disposition === 'queued',
			),
	);
}

function hasTerminalRenderReceipt(
	messages: readonly BridgeWorkerMainToServerMessage[],
	expected: {
		readonly disposition: 'rejected' | 'superseded';
		readonly itemId: string;
	},
): boolean {
	return messages.some(
		(message): boolean =>
			message.command === 'renderDisposition' &&
			message.receipts.some(
				(receipt): boolean =>
					receipt.itemId === expected.itemId &&
					receipt.disposition === expected.disposition &&
					receipt.reason === 'stale_submission',
			),
	);
}

function filePublications(
	postedMessages: readonly PostedBridgeWorkerRuntimeMessage[],
): readonly BridgeWorkerFilePierreRenderJobEvent[] {
	return postedMessages.flatMap(({ message }) =>
		message.kind === 'filePierreRenderJob' ? [message] : [],
	);
}

function requireFilePublication(
	postedMessages: readonly PostedBridgeWorkerRuntimeMessage[],
	index: number,
): BridgeWorkerFilePierreRenderJobEvent {
	const publication = filePublications(postedMessages)[index];
	if (publication === undefined) throw new Error(`Expected File publication ${index + 1}.`);
	return publication;
}
