import { act } from 'react';

import type { BridgeCommWorkerPort } from '../core/comm-worker/bridge-comm-worker-entry.js';
import { encodeBridgeWorkerActiveViewerModeUpdateCommand } from '../core/comm-worker/bridge-comm-worker-protocol.js';
import { registerBridgeCommWorkerRuntimePortProtocol } from '../core/comm-worker/bridge-comm-worker-runtime-protocol.js';
import type {
	BridgePaneCommWorkerDispatcher,
	BridgePaneCommWorkerNativeBootstrap,
} from '../core/comm-worker/bridge-pane-comm-worker-session.js';
import type { BridgePaneSessionPort } from '../core/comm-worker/bridge-pane-runtime.js';
import { BridgeProductBoundedAsyncQueue } from '../core/comm-worker/bridge-product-async-queue.js';
import type { BridgeProductCallResult } from '../core/comm-worker/bridge-product-call-contracts.js';
import {
	bridgeProductFileContentDescriptorSchema,
	type BridgeProductContentFrameFor,
} from '../core/comm-worker/bridge-product-content-contracts.js';
import type {
	BridgeProductSubscriptionEvent,
	BridgeProductSubscriptionUpdateOptions,
} from '../core/comm-worker/bridge-product-subscription-contracts.js';
import type { BridgeProductSubscription } from '../core/comm-worker/bridge-product-transport-contract.js';
import type { BridgeProductTransportSession } from '../core/comm-worker/bridge-product-transport.js';
import {
	bridgeWorkerServerToMainMessageSchema,
	type BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import { bridgeWorkerPierreRenderPolicy } from '../core/demand/bridge-content-demand-policy.js';
import { waitForBridgeViewerAnimationFrame } from '../review-viewer/test-support/bridge-viewer-browser-dom.js';
import type { BridgeFileViewerBrowserTestProductSession } from './bridge-file-viewer-browser-test-app.js';
import {
	fileContentSha256Hex,
	type PublishFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';

export type BridgeFileViewerBrowserTestPaneSessionFactory = () => BridgePaneSessionPort;

interface BridgeFileViewerBrowserWorkerMessageDrain {
	readonly wait: () => Promise<void>;
}

const activeBridgeFileViewerBrowserWorkerMessageDrains =
	new Set<BridgeFileViewerBrowserWorkerMessageDrain>();
const bridgeFileViewerBrowserWorkerDrainRequestPrefix = 'browser-file-worker-drain-';

export async function waitForBridgeFileViewerWorkerMessageDrain(): Promise<void> {
	await Promise.all(
		Array.from(activeBridgeFileViewerBrowserWorkerMessageDrains, (drain) => drain.wait()),
	);
}

export function createBridgeFileViewerBrowserTestPaneSessionFactory(props: {
	readonly productSessionRef: {
		readonly current: BridgeFileViewerBrowserTestProductSession | undefined;
	};
}): BridgeFileViewerBrowserTestPaneSessionFactory {
	let workerMessageActQueue: Promise<void> = Promise.resolve();
	let fileSourceDiscoveryCompleted = false;
	let pendingFileDisplayPatchCount = 0;
	let pendingMetadataInterestUpdateCount = 0;
	let pendingSettledContentPierreJobCount = 0;
	let pendingSettledContentTerminalPatchCount = 0;
	const pendingFileDisplayPatchWaiters = new Set<() => void>();
	let waitForWorkerToMainPortDrain: (() => Promise<void>) | null = null;
	const waitForStableWorkerMessageDrain = async (stableFrameCount = 0): Promise<void> => {
		if (
			!fileSourceDiscoveryCompleted ||
			pendingFileDisplayPatchCount > 0 ||
			pendingMetadataInterestUpdateCount > 0 ||
			pendingSettledContentPierreJobCount > 0 ||
			pendingSettledContentTerminalPatchCount > 0
		) {
			await new Promise<void>((resolve): void => {
				pendingFileDisplayPatchWaiters.add(resolve);
			});
		}
		await waitForWorkerToMainPortDrain?.();
		const observedActQueue = workerMessageActQueue;
		await observedActQueue;
		await act(async (): Promise<void> => {
			await waitForBridgeViewerAnimationFrame();
		});
		await waitForWorkerToMainPortDrain?.();
		const finalActQueue = workerMessageActQueue;
		await finalActQueue;
		await Promise.resolve();
		if (
			fileSourceDiscoveryCompleted &&
			pendingFileDisplayPatchCount === 0 &&
			pendingMetadataInterestUpdateCount === 0 &&
			pendingSettledContentPierreJobCount === 0 &&
			pendingSettledContentTerminalPatchCount === 0 &&
			finalActQueue === workerMessageActQueue
		) {
			if (stableFrameCount >= 1) return;
			await waitForStableWorkerMessageDrain(stableFrameCount + 1);
			return;
		}
		await waitForStableWorkerMessageDrain(0);
	};
	const workerMessageDrain: BridgeFileViewerBrowserWorkerMessageDrain = {
		wait: waitForStableWorkerMessageDrain,
	};
	const publishWorkerMessagesInAct = (publishProps: {
		readonly messages: readonly BridgeWorkerServerToMainMessage[];
		readonly publishWorkerMessages: (messages: readonly BridgeWorkerServerToMainMessage[]) => void;
	}): void => {
		const publishCompletion = workerMessageActQueue.then(async (): Promise<void> => {
			await act(async (): Promise<void> => {
				publishProps.publishWorkerMessages(publishProps.messages);
				await Promise.resolve();
			});
		});
		workerMessageActQueue = publishCompletion.catch((error: unknown) => {
			queueMicrotask((): void => {
				throw error;
			});
		});
	};
	return (): BridgePaneSessionPort => ({
		createDispatcher: (dispatcherProps): BridgePaneCommWorkerDispatcher => {
			const channel = new MessageChannel();
			let workerDrainRequestSequence = 0;
			const workerDrainWaiters = new Map<string, () => void>();
			waitForWorkerToMainPortDrain = (): Promise<void> => {
				workerDrainRequestSequence += 1;
				const requestId = `${bridgeFileViewerBrowserWorkerDrainRequestPrefix}${workerDrainRequestSequence}`;
				const completion = new Promise<void>((resolve): void => {
					workerDrainWaiters.set(requestId, resolve);
				});
				channel.port2.postMessage({
					direction: 'serverWorkerToMain',
					kind: 'health',
					requestId,
					status: 'ready',
					transferDescriptors: [],
					wireVersion: 1,
				});
				return completion;
			};
			activeBridgeFileViewerBrowserWorkerMessageDrains.add(workerMessageDrain);
			const productTransport = createBrowserTestProductTransport({
				onContentTerminalSettled: (succeeded): void => {
					pendingSettledContentTerminalPatchCount += 1;
					if (succeeded) pendingSettledContentPierreJobCount += 1;
				},
				onFileSourceDiscoveryCompleted: (): void => {
					fileSourceDiscoveryCompleted = true;
					for (const resolve of pendingFileDisplayPatchWaiters) resolve();
					pendingFileDisplayPatchWaiters.clear();
				},
				onMetadataEventsPublished: (eventCount): void => {
					pendingFileDisplayPatchCount += eventCount;
				},
				onMetadataInterestUpdateSettled: (): void => {
					void Promise.resolve()
						.then(() => Promise.resolve())
						.then((): void => {
							pendingMetadataInterestUpdateCount -= 1;
							if (pendingMetadataInterestUpdateCount === 0) {
								for (const resolve of pendingFileDisplayPatchWaiters) resolve();
								pendingFileDisplayPatchWaiters.clear();
							}
						});
				},
				onMetadataInterestUpdateStarted: (): void => {
					pendingMetadataInterestUpdateCount += 1;
				},
				productSessionRef: props.productSessionRef,
			});
			channel.port1.addEventListener('message', (event: MessageEvent<unknown>): void => {
				const message = bridgeWorkerServerToMainMessageSchema.parse(event.data);
				if (
					message.kind === 'health' &&
					message.requestId?.startsWith(bridgeFileViewerBrowserWorkerDrainRequestPrefix) === true
				) {
					workerDrainWaiters.get(message.requestId)?.();
					workerDrainWaiters.delete(message.requestId);
					return;
				}
				if (message.kind === 'fileDisplayPatch' && pendingFileDisplayPatchCount > 0) {
					pendingFileDisplayPatchCount -= 1;
					if (pendingFileDisplayPatchCount === 0) {
						for (const resolve of pendingFileDisplayPatchWaiters) resolve();
						pendingFileDisplayPatchWaiters.clear();
					}
				}
				if (message.kind === 'filePierreRenderJob' && pendingSettledContentPierreJobCount > 0) {
					pendingSettledContentPierreJobCount -= 1;
					if (pendingSettledContentPierreJobCount === 0) {
						for (const resolve of pendingFileDisplayPatchWaiters) resolve();
						pendingFileDisplayPatchWaiters.clear();
					}
				}
				if (
					message.kind === 'fileRenderPatch' &&
					message.patches.some(
						(patch) =>
							patch.slice === 'contentAvailability' &&
							patch.operation === 'upsert' &&
							patch.payload.state !== 'loading',
					) &&
					pendingSettledContentTerminalPatchCount > 0
				) {
					pendingSettledContentTerminalPatchCount -= 1;
					if (pendingSettledContentTerminalPatchCount === 0) {
						for (const resolve of pendingFileDisplayPatchWaiters) resolve();
						pendingFileDisplayPatchWaiters.clear();
					}
				}
				publishWorkerMessagesInAct({
					messages: [message],
					publishWorkerMessages: dispatcherProps.publishWorkerMessages,
				});
			});
			registerBridgeCommWorkerRuntimePortProtocol(channel.port2 as BridgeCommWorkerPort, {
				bridgeDemandRank: { lane: 'selected', priority: 0 },
				budget: bridgeWorkerPierreRenderPolicy.reviewInteractiveRenderBudget,
				fileViewBudget: {
					className: 'interactive',
					maxBytes: 2 * 1024 * 1024,
					maxWindowLines: 10_000,
				},
				productTransport,
			});
			channel.port1.start();
			channel.port2.start();
			channel.port1.postMessage(
				encodeBridgeWorkerActiveViewerModeUpdateCommand({
					epoch: 1,
					requestId: 'browser-file-worker-active-viewer-mode',
					update: {
						activeSource: null,
						mode: 'file',
						nativeSelectionRequestId: null,
						sequence: 1,
						sessionId: 'browser-file-worker-session',
					},
				}),
			);
			props.productSessionRef.current?.onWorkerMessagesPublisher?.((messages): void => {
				dispatcherProps.publishWorkerMessages(messages);
			});
			return {
				dispatch: (message): void => {
					props.productSessionRef.current?.onWorkerCommand?.(message);
					channel.port1.postMessage(message);
				},
				dispose: (): void => {
					activeBridgeFileViewerBrowserWorkerMessageDrains.delete(workerMessageDrain);
					waitForWorkerToMainPortDrain = null;
					fileSourceDiscoveryCompleted = true;
					pendingFileDisplayPatchCount = 0;
					pendingMetadataInterestUpdateCount = 0;
					pendingSettledContentPierreJobCount = 0;
					pendingSettledContentTerminalPatchCount = 0;
					for (const resolve of pendingFileDisplayPatchWaiters) resolve();
					pendingFileDisplayPatchWaiters.clear();
					for (const resolve of workerDrainWaiters.values()) resolve();
					workerDrainWaiters.clear();
					channel.port1.close();
					channel.port2.close();
				},
			};
		},
		dispose: (): void => {},
		installNativeBootstrap: (_bootstrap: BridgePaneCommWorkerNativeBootstrap): void => {},
	});
}

function createBrowserTestProductTransport(props: {
	readonly onContentTerminalSettled: (succeeded: boolean) => void;
	readonly onFileSourceDiscoveryCompleted: () => void;
	readonly onMetadataEventsPublished: (eventCount: number) => void;
	readonly onMetadataInterestUpdateSettled: () => void;
	readonly onMetadataInterestUpdateStarted: () => void;
	readonly productSessionRef: {
		readonly current: BridgeFileViewerBrowserTestProductSession | undefined;
	};
}): BridgeProductTransportSession {
	let fileEpoch = 0;
	return {
		bumpWorkerDerivationEpoch: (surface): number => {
			if (surface === 'file') fileEpoch += 1;
			return surface === 'file' ? fileEpoch : 0;
		},
		call: async (...arguments_): Promise<never> => {
			const [method] = arguments_;
			if (method === 'file.source.current') {
				try {
					return (await (props.productSessionRef.current?.currentSource?.() ??
						defaultBrowserTestCurrentSource())) as never;
				} finally {
					props.onFileSourceDiscoveryCompleted();
				}
			}
			if (method === 'file.activeViewerMode.update') return null as never;
			throw new Error(`Unexpected browser-test product call: ${method}.`);
		},
		openContent: (descriptor, signal): never => {
			const fileDescriptor = bridgeProductFileContentDescriptorSchema.parse(descriptor);
			const content = Promise.resolve(
				props.productSessionRef.current?.readContent?.({ descriptor: fileDescriptor, signal }) ??
					defaultBrowserTestContent(fileDescriptor.descriptorId),
			);
			const terminal = content.then(async (text) => {
				const bytes = new TextEncoder().encode(text);
				return {
					bytes: bytes.buffer,
					contentKind: 'file.content' as const,
					descriptorId: fileDescriptor.descriptorId,
					kind: 'complete' as const,
					observedSha256: await fileContentSha256Hex(bytes),
				};
			});
			void terminal.then(
				(): void => {
					props.onContentTerminalSettled(true);
				},
				(): void => {
					props.onContentTerminalSettled(false);
				},
			);
			return {
				contentKind: 'file.content',
				contentRequestId: `browser-content-${fileDescriptor.descriptorId}`,
				frames: emptyBrowserTestContentFrames(),
				terminal,
			} as never;
		},
		setPanePresentationFrameSink: (sink): void => {
			// This fixture models an already active native File pane. Activity-suppression
			// tests use their own transports so dormant and hidden admission remain explicit.
			sink({
				activityRevision: 1,
				kind: 'pane.presentation',
				metadataStreamId: 'browser-file-test-metadata-stream',
				nativeActivity: 'foreground',
				paneSessionId: 'browser-file-test-pane-session',
				refreshingLanes: [],
				streamSequence: 1,
				wireVersion: 2,
				workerInstanceId: 'browser-file-test-worker-instance',
			});
		},
		subscribe: (...arguments_): never => {
			const [subscriptionKind, options] = arguments_;
			if (subscriptionKind !== 'file.metadata') {
				throw new Error(`Unexpected browser-test product subscription: ${subscriptionKind}.`);
			}
			const events = new BridgeProductBoundedAsyncQueue<
				BridgeProductSubscriptionEvent<'file.metadata'>
			>(256);
			const publish: PublishFileMetadataEvents = (publishedEvents): void => {
				props.onMetadataEventsPublished(publishedEvents.length);
				for (const event of publishedEvents) events.push(event);
			};
			const session = props.productSessionRef.current;
			session?.onMetadataSubscriptionOpen?.(options as never);
			publish(session?.initialMetadataEvents ?? []);
			session?.onMetadataSubscription?.(publish);
			const subscription: BridgeProductSubscription<'file.metadata'> = {
				cancel: async (): Promise<void> => {
					events.close(true);
				},
				events,
				subscriptionId: 'browser-file-metadata-subscription',
				subscriptionKind: 'file.metadata',
				update: async (
					updatedOptions: BridgeProductSubscriptionUpdateOptions<'file.metadata'>,
				): Promise<void> => {
					props.onMetadataInterestUpdateStarted();
					try {
						await props.productSessionRef.current?.onMetadataInterestUpdate?.(updatedOptions);
					} finally {
						props.onMetadataInterestUpdateSettled();
					}
				},
			};
			return subscription as never;
		},
		workerDerivationEpoch: (surface): number => (surface === 'file' ? fileEpoch : 0),
	};
}

function defaultBrowserTestCurrentSource(): BridgeProductCallResult<'file.source.current'> {
	return {
		status: 'available',
		source: {
			cwdScope: null,
			freshness: 'live',
			includeStatuses: true,
			repoId: '00000000-0000-4000-8000-000000000001',
			rootPathToken: 'browser-test-root',
			worktreeId: '00000000-0000-4000-8000-000000000002',
		},
	};
}

function defaultBrowserTestContent(descriptorId: string): string {
	return `export const ${descriptorId.replaceAll('-', '_')} = true;\n`;
}

async function* emptyBrowserTestContentFrames(): AsyncIterable<
	BridgeProductContentFrameFor<'file.content'>
> {}
