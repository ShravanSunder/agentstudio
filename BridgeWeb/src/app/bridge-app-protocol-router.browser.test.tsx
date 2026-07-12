import type { ReactElement } from 'react';
import { afterEach, describe, expect, test, vi } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode geometry assertions need app CSS.
import './bridge-app.css';
import type { BridgeRPCCommand } from '../bridge/bridge-rpc-client.js';
import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerMainToServerMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeIntakeFrame } from '../core/models/bridge-intake-frame.js';
import { buildReviewMetadataSnapshotFrame } from '../features/review/protocol/review-metadata-frame-builder.js';
import type { BridgeFileViewerBrowserTestProductSession } from '../file-viewer/bridge-file-viewer-browser-test-app.js';
import {
	makeSourceAcceptedMetadataEvent,
	makeSourceIdentity,
	type PublishFileMetadataEvents,
} from '../file-viewer/bridge-file-viewer-browser-test-fixtures.js';
import { createBridgeFileViewerBrowserTestCommWorkerTransportFactory } from '../file-viewer/bridge-file-viewer-browser-test-harness.js';
import { BridgeFileViewerRuntimeTransportFactoryProvider } from '../file-viewer/bridge-file-viewer-render-snapshot-controller.js';
import { makeBridgeReviewPackage } from '../foundation/review-package/bridge-review-package-test-support.js';
import {
	actClick,
	actUpdate,
	actWait,
	createInProcessBridgeReviewWorkerTransportFactory,
	installBridgeReadyHandshake,
	type InProcessBridgeReviewWorkerTransportFactory,
	pollWithinAct,
	pollWithinActUntilEqual,
	pollWithinActUntilTruthy,
	recordBridgeSchemeRPCFetch,
} from './bridge-app-native-review-error.browser.test-support.js';
import {
	BridgeAppProtocolRouter,
	resolveBridgeAppProtocolFromElement,
} from './bridge-app-protocol-router.js';
import { BridgeApp } from './bridge-app.js';

type ActiveViewerModeUpdateDetail = Extract<
	BridgeRPCCommand,
	{ readonly method: 'bridge.activeViewerMode.update' }
>;

let activeDisposers: readonly (() => void)[] = [];

function registerDisposer(dispose: () => void): void {
	activeDisposers = [...activeDisposers, dispose];
}

describe('BridgeAppProtocolRouter', () => {
	afterEach(async () => {
		cleanup();
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		for (const dispose of activeDisposers) {
			dispose();
		}
		activeDisposers = [];
		document.body.replaceChildren();
		document.documentElement.removeAttribute('data-bridge-app-protocol');
		document.documentElement.removeAttribute('data-bridge-review-pane-id');
		document.documentElement.removeAttribute('data-bridge-review-stream-id');
		vi.restoreAllMocks();
	});

	test('defaults to Review when no app protocol is declared', async () => {
		render(<BridgeAppProtocolRouter />);

		const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
		const contextSwitcher = document.querySelector(
			'[data-testid="bridge-viewer-context-switcher"]',
		);
		const fileContextButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
		const reviewContextButton = document.querySelector(
			'[data-testid="bridge-viewer-context-review"]',
		);
		expect(appRoot?.getAttribute('data-bridge-app-owner')).toBe('BridgeApp');
		expect(appRoot?.getAttribute('data-bridge-viewer-shell-owner')).toBe('BridgeViewerAppShell');
		expect(appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('review');
		expect(contextSwitcher).not.toBeNull();
		expect(fileContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('false');
		expect(reviewContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('true');
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).not.toBeNull();
		assertSharedResizableRailFallbackGeometry({
			contentPanelTestId: 'bridge-review-content-panel',
			frameTestId: 'bridge-review-fallback-frame',
			handleId: 'bridge-review-rail-resize-handle',
			railPanelTestId: 'bridge-review-resizable-rail',
		});
		expect(document.querySelector('[data-testid="worktree-file-app"]')).toBeNull();
	});

	test('routes Worktree/File protocol through the shared Bridge app shell', async () => {
		render(<BridgeAppProtocolRouter protocol="worktree-file" />);

		expect(document.querySelector('[data-testid="worktree-file-app"]')).toBeNull();
		const appRoot = document.querySelector('[data-testid="bridge-app-root"]');
		const contextSwitcher = document.querySelector(
			'[data-testid="bridge-viewer-context-switcher"]',
		);
		const contentTopbar = document.querySelector('[data-testid="bridge-viewer-content-topbar"]');
		const fileContextButton = document.querySelector('[data-testid="bridge-viewer-context-file"]');
		const reviewContextButton = document.querySelector(
			'[data-testid="bridge-viewer-context-review"]',
		);
		const modeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-file"]');
		const reviewModeHost = document.querySelector('[data-testid="bridge-viewer-mode-host-review"]');
		const lazyLoadingFrame = document.querySelector(
			'[data-testid="bridge-file-viewer-lazy-loading-frame"]',
		);
		expect(appRoot?.getAttribute('data-bridge-app-owner')).toBe('BridgeApp');
		expect(appRoot?.getAttribute('data-bridge-viewer-shell-owner')).toBe('BridgeViewerAppShell');
		expect(appRoot?.getAttribute('data-bridge-viewer-mode')).toBe('file');
		expect(contentTopbar?.getAttribute('data-bridge-viewer-content-topbar')).toBe('true');
		expect(contextSwitcher?.closest('[data-testid="bridge-viewer-content-topbar"]')).toBe(
			contentTopbar,
		);
		expect(contextSwitcher).not.toBeNull();
		expect(fileContextButton?.getAttribute('data-slot')).toBe('button');
		expect(fileContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('true');
		expect(reviewContextButton?.getAttribute('data-slot')).toBe('button');
		expect(reviewContextButton?.getAttribute('data-bridge-viewer-context-selected')).toBe('false');
		expect(modeHost?.parentElement).toBe(appRoot);
		expect(modeHost?.getAttribute('data-bridge-viewer-mode-active')).toBe('true');
		expect(modeHost?.className).not.toContain('pt-9');
		expect(reviewModeHost?.parentElement).toBe(appRoot);
		expect(reviewModeHost?.getAttribute('data-bridge-viewer-mode-active')).toBe('false');
		expect(reviewModeHost?.hasAttribute('hidden')).toBe(true);
		expect(document.querySelectorAll('[data-slot="resizable-panel-group"]')).toHaveLength(1);
		expect(document.querySelector('[data-testid="bridge-review-empty-shell"]')).not.toBeNull();
		expect(lazyLoadingFrame?.parentElement).toBe(modeHost);
		assertSharedResizableRailFallbackGeometry({
			contentPanelTestId: 'bridge-file-viewer-content-panel',
			frameTestId: 'bridge-file-viewer-lazy-loading-frame',
			handleId: 'bridge-file-viewer-rail-resize-handle',
			railPanelTestId: 'bridge-file-viewer-resizable-rail',
		});
		await actClick(requireActiveContextButton('review'));
		expect(
			await pollWithinActUntilEqual(
				() => appRoot?.getAttribute('data-bridge-viewer-mode'),
				'review',
			),
		).toBe('review');
		expect(document.querySelectorAll('[data-slot="resizable-panel-group"]')).toHaveLength(1);
		assertSharedResizableRailFallbackGeometry({
			contentPanelTestId: 'bridge-review-content-panel',
			frameTestId: 'bridge-review-fallback-frame',
			handleId: 'bridge-review-rail-resize-handle',
			railPanelTestId: 'bridge-review-resizable-rail',
		});
		await actClick(requireActiveContextButton('file'));
		expect(
			await pollWithinActUntilEqual(() => appRoot?.getAttribute('data-bridge-viewer-mode'), 'file'),
		).toBe('file');
		expect(document.querySelectorAll('[data-slot="resizable-panel-group"]')).toHaveLength(1);
		assertSharedResizableRailFallbackGeometry({
			contentPanelTestId: 'bridge-file-viewer-content-panel',
			frameTestId: 'bridge-file-viewer-lazy-loading-frame',
			handleId: 'bridge-file-viewer-rail-resize-handle',
			railPanelTestId: 'bridge-file-viewer-resizable-rail',
		});
		expect(document.querySelector('[data-testid="bridge-file-viewer-shell"]')).toBeNull();
	});

	test('starts typed File source discovery when the File route mounts', async () => {
		let sourceDiscoveryCount = 0;
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);

		renderFileProductApp(<BridgeAppProtocolRouter protocol="worktree-file" />, {
			...activeFileProductSession(),
			currentSource: () => {
				sourceDiscoveryCount += 1;
				return availableFileSource();
			},
		});

		expect(await pollWithinActUntilEqual(() => sourceDiscoveryCount, 1)).toBe(1);
	});

	test('emits active viewer mode notifications with monotonic sequence across mode switches', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});

		renderFileProductApp(
			<BridgeAppProtocolRouter
				protocol="worktree-file"
				reviewWorkerTransportFactory={createRecordingBridgeWorkerTransportFactory(commandDetails)}
			/>,
			activeFileProductSession(),
		);

		expect(
			await pollWithinActUntilTruthy(() =>
				activeViewerModeUpdates(commandDetails).some(hasWorktreeFileActiveSource),
			),
		).toBe(true);
		await actClick(requireActiveContextButton('review'));
		expect(
			await pollWithinActUntilTruthy(() =>
				activeViewerModeUpdates(commandDetails).some((detail) => detail.params.mode === 'review'),
			),
		).toBe(true);
		await actClick(requireActiveContextButton('file'));
		expect(
			await pollWithinAct({
				getValue: () =>
					activeViewerModeUpdates(commandDetails).filter((detail) => detail.params.mode === 'file')
						.length,
				isSatisfied: (count): boolean => count >= 2,
			}),
		).toBeGreaterThanOrEqual(2);

		const updates = activeViewerModeUpdates(commandDetails);
		expect(updates.map((detail) => detail.params.sequence)).toEqual(
			updates.map((detail) => detail.params.sequence).toSorted((left, right) => left - right),
		);
		expect(new Set(updates.map((detail) => detail.params.sessionId)).size).toBe(1);
	});

	test('does not retry active viewer mode notification after ambiguous scheme RPC failure', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		let failedActiveSourceAttemptCount = 0;
		const transportFactory = createRecordingBridgeWorkerTransportFactory(
			commandDetails,
			(command): void => {
				if (
					isActiveViewerModeUpdate(command) &&
					hasWorktreeFileActiveSource(command) &&
					failedActiveSourceAttemptCount === 0
				) {
					failedActiveSourceAttemptCount += 1;
					throw new Error('temporary active viewer failure');
				}
			},
		);
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);

		renderFileProductApp(
			<BridgeAppProtocolRouter
				protocol="worktree-file"
				reviewWorkerTransportFactory={transportFactory}
			/>,
			activeFileProductSession(),
		);

		expect(
			await pollWithinActUntilEqual(
				() => activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource).length,
				1,
			),
		).toBe(1);
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		expect(
			activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource),
		).toHaveLength(1);
		expect(failedActiveSourceAttemptCount).toBe(1);
	});

	test('retries active viewer mode notification after worker transport failure', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		let failedTransportAttemptCount = 0;
		const delegateTransportFactory = createRecordingBridgeWorkerTransportFactory(commandDetails);
		const transportFactory: InProcessBridgeReviewWorkerTransportFactory = (props) => {
			const delegateTransport = delegateTransportFactory(props);
			return {
				dispatch: (message: BridgeWorkerMainToServerMessage): void => {
					if (failedTransportAttemptCount === 0 && isWorktreeFileActiveViewerModeCommand(message)) {
						failedTransportAttemptCount += 1;
						props.publishWorkerMessages([
							{
								wireVersion: BRIDGE_WORKER_WIRE_VERSION,
								direction: 'serverWorkerToMain',
								kind: 'health',
								requestId: message.requestId,
								status: 'degraded',
								message:
									'Bridge comm worker transport failed before bridge.activeViewerMode.update delivery.',
								transferDescriptors: [],
							},
						]);
						return;
					}
					delegateTransport.dispatch(message);
				},
				dispose: (): void => {
					delegateTransport.dispose();
				},
			};
		};
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});

		renderFileProductApp(
			<BridgeAppProtocolRouter
				protocol="worktree-file"
				reviewWorkerTransportFactory={transportFactory}
			/>,
			activeFileProductSession(),
		);

		expect(
			await pollWithinAct({
				getValue: () =>
					activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource).length,
				isSatisfied: (count): boolean => count >= 1,
			}),
		).toBe(1);
		expect(failedTransportAttemptCount).toBe(1);
	});

	test('retries active viewer mode notification after queued bootstrap degradation', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		let degradedBootstrapAttemptCount = 0;
		const delegateTransportFactory = createRecordingBridgeWorkerTransportFactory(commandDetails);
		const transportFactory: InProcessBridgeReviewWorkerTransportFactory = (props) => {
			const delegateTransport = delegateTransportFactory(props);
			return {
				dispatch: (message: BridgeWorkerMainToServerMessage): void => {
					if (
						degradedBootstrapAttemptCount === 0 &&
						isWorktreeFileActiveViewerModeCommand(message)
					) {
						degradedBootstrapAttemptCount += 1;
						props.publishWorkerMessages([
							{
								wireVersion: BRIDGE_WORKER_WIRE_VERSION,
								direction: 'serverWorkerToMain',
								kind: 'health',
								requestId: 'active-viewer-mode-worker-bootstrap',
								status: 'degraded',
								message: 'Bridge comm worker runtime was already bootstrapped.',
								transferDescriptors: [],
							},
							{
								wireVersion: BRIDGE_WORKER_WIRE_VERSION,
								direction: 'serverWorkerToMain',
								kind: 'health',
								requestId: message.requestId,
								status: 'degraded',
								message:
									'Bridge comm worker transport failed before bridge.activeViewerMode.update delivery.',
								transferDescriptors: [],
							},
						]);
						return;
					}
					delegateTransport.dispatch(message);
				},
				dispose: (): void => {
					delegateTransport.dispose();
				},
			};
		};
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});

		renderFileProductApp(
			<BridgeAppProtocolRouter
				protocol="worktree-file"
				reviewWorkerTransportFactory={transportFactory}
			/>,
			activeFileProductSession(),
		);

		expect(
			await pollWithinAct({
				getValue: () =>
					activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource).length,
				isSatisfied: (count): boolean => count >= 1,
			}),
		).toBe(1);
		expect(degradedBootstrapAttemptCount).toBe(1);
	});

	test('does not retry active viewer mode notification after ambiguous in-flight worker failure', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		let ambiguousFailureCount = 0;
		const delegateTransportFactory = createRecordingBridgeWorkerTransportFactory(commandDetails);
		const transportFactory: InProcessBridgeReviewWorkerTransportFactory = (props) => {
			const delegateTransport = delegateTransportFactory(props);
			return {
				dispatch: (message: BridgeWorkerMainToServerMessage): void => {
					delegateTransport.dispatch(message);
					if (ambiguousFailureCount === 0 && isWorktreeFileActiveViewerModeCommand(message)) {
						ambiguousFailureCount += 1;
						props.publishWorkerMessages([
							{
								wireVersion: BRIDGE_WORKER_WIRE_VERSION,
								direction: 'serverWorkerToMain',
								kind: 'health',
								requestId: message.requestId,
								status: 'degraded',
								message:
									'Bridge comm worker transport lost confirmation after bridge.activeViewerMode.update dispatch.',
								deliveryStatus: 'unknownAfterDispatch',
								transferDescriptors: [],
							},
						]);
					}
				},
				dispose: (): void => {
					delegateTransport.dispose();
				},
			};
		};
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});

		renderFileProductApp(
			<BridgeAppProtocolRouter
				protocol="worktree-file"
				reviewWorkerTransportFactory={transportFactory}
			/>,
			activeFileProductSession(),
		);

		expect(
			await pollWithinActUntilEqual(
				() => activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource).length,
				1,
			),
		).toBe(1);
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		expect(
			activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource),
		).toHaveLength(1);
		expect(ambiguousFailureCount).toBe(1);
	});

	test('does not duplicate active viewer mode notification when telemetry bootstrap rerenders the app', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		let resolveFirstActiveSourceResponse: (() => void) | null = null;
		registerDisposer(
			installBridgeReadyHandshake({ pushNonce: 'push-telemetry-bootstrap' }).dispose,
		);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			const response = recordBridgeSchemeRPCFetch(input, init, commandDetails);
			const detail = commandDetails.at(-1);
			if (
				response !== null &&
				isActiveViewerModeUpdate(detail) &&
				hasWorktreeFileActiveSource(detail) &&
				resolveFirstActiveSourceResponse === null
			) {
				return await new Promise<Response>((resolve): void => {
					resolveFirstActiveSourceResponse = (): void => {
						resolve(response);
					};
				});
			}
			return response ?? new Response('unexpected request', { status: 404 });
		});

		renderFileProductApp(
			<BridgeAppProtocolRouter
				protocol="worktree-file"
				reviewWorkerTransportFactory={createRecordingBridgeWorkerTransportFactory(commandDetails)}
			/>,
			activeFileProductSession(),
		);

		expect(
			await pollWithinActUntilEqual(
				() => activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource).length,
				1,
			),
		).toBe(1);
		await actUpdate((): void => {
			document.dispatchEvent(
				new CustomEvent('__bridge_handshake', {
					detail: {
						pushNonce: 'push-telemetry-bootstrap',
						telemetryConfig: {
							enabledScopes: ['web', 'webkit'],
							endpointUrl: 'agentstudio://telemetry/batch',
							maxEncodedBatchBytes: 16_384,
							maxSamplesPerBatch: 64,
							minimumFlushIntervalMilliseconds: 250,
							scenario: 'bridge-runtime',
							viewerOpenEpochUnixMillis: 1_783_520_000_000,
							viewerOpenTraceparent: '00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00',
						},
					},
				}),
			);
		});
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		expect(
			activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource),
		).toHaveLength(1);
		await actUpdate((): void => {
			resolveFirstActiveSourceResponse?.();
		});
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
	});

	test('does not open active viewer mode notifications after bridge-ready error', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		registerDisposer(
			installBridgeReadyHandshake({
				pushNonce: 'push-ready-error',
				readyErrorMessage: 'ready acknowledgement failed',
			}).dispose,
		);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});

		renderFileProductApp(
			<BridgeAppProtocolRouter
				protocol="worktree-file"
				reviewWorkerTransportFactory={createRecordingBridgeWorkerTransportFactory(commandDetails)}
			/>,
			activeFileProductSession(),
		);

		const activeViewerUpdateCount = await pollWithinAct({
			getValue: () => activeViewerModeUpdates(commandDetails).length,
			isSatisfied: (count): boolean => count > 0,
			timeoutMilliseconds: 200,
		});
		expect(activeViewerUpdateCount).toBe(0);
	});

	test('active viewer mode notifications match the committed mode through rapid transitions', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		const mismatchedUpdates: ActiveViewerModeUpdateDetail[] = [];
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			const response = recordBridgeSchemeRPCFetch(input, init, commandDetails);
			if (response === null) {
				return new Response('unexpected request', { status: 404 });
			}
			const detail = commandDetails.at(-1);
			if (!isActiveViewerModeUpdate(detail)) {
				return response;
			}
			const committedMode = activeViewerMode();
			if (committedMode !== null && committedMode !== detail.params.mode) {
				mismatchedUpdates.push(detail);
			}
			return response;
		});

		renderFileProductApp(
			<BridgeAppProtocolRouter
				protocol="review"
				reviewWorkerTransportFactory={createRecordingBridgeWorkerTransportFactory(commandDetails)}
			/>,
			activeFileProductSession(),
		);
		expect(await pollWithinActUntilEqual(activeViewerMode, 'review')).toBe('review');

		await actClick(requireActiveContextButton('file'));
		await actWait(() => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));
		await actClick(requireActiveContextButton('review'));
		await actWait(() => new Promise<void>((resolve) => requestAnimationFrame(() => resolve())));
		await actClick(requireActiveContextButton('file'));
		expect(await pollWithinActUntilEqual(activeViewerMode, 'file')).toBe('file');
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));

		expect(mismatchedUpdates).toEqual([]);
	});

	test('review active mode waits for current review source and dedupes source identity', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		const streamId = 'review:bridge-app-test-pane';
		const reviewPackage = makeBridgeReviewPackage();
		const snapshotFrame = buildReviewMetadataSnapshotFrame({
			package: reviewPackage,
			paneId: 'bridge-app-test-pane',
			sourceIdentity: 'bridge-app-test-source',
			streamId,
			sequence: 0,
			selectedItemId: reviewPackage.orderedItemIds[0] ?? null,
			visibleItemIds: reviewPackage.orderedItemIds,
		});
		document.documentElement.setAttribute('data-bridge-review-pane-id', 'bridge-app-test-pane');
		document.documentElement.setAttribute('data-bridge-review-stream-id', streamId);
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-review-source' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});

		render(
			<BridgeAppProtocolRouter
				projectionWorkerClient={null}
				protocol="review"
				reviewWorkerTransportFactory={createRecordingBridgeWorkerTransportFactory(commandDetails)}
			/>,
		);
		expect(await pollWithinActUntilEqual(activeViewerMode, 'review')).toBe('review');
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		expect(activeViewerModeUpdates(commandDetails)).toHaveLength(0);

		await dispatchIntakeFrame({
			generation: snapshotFrame.generation,
			kind: 'snapshot',
			nonce: 'push-review-source',
			payload: snapshotFrame,
			sequence: snapshotFrame.sequence,
			streamId,
		});
		expect(
			await pollWithinActUntilEqual(
				() => activeViewerModeUpdates(commandDetails).filter(hasReviewActiveSource).length,
				1,
			),
		).toBe(1);

		await dispatchIntakeFrame({
			generation: snapshotFrame.generation,
			kind: 'snapshot',
			nonce: 'push-review-source',
			payload: snapshotFrame,
			sequence: snapshotFrame.sequence + 1,
			streamId,
		});
		await actWait(() => new Promise<void>((resolve) => window.setTimeout(resolve, 0)));
		expect(activeViewerModeUpdates(commandDetails).filter(hasReviewActiveSource)).toHaveLength(1);
	});

	test('dedupes file active source when the same typed source is published again', async () => {
		const commandDetails: BridgeRPCCommand[] = [];
		let publishMetadataEvents: PublishFileMetadataEvents | null = null;
		const reviewWorkerTransportFactory =
			createRecordingBridgeWorkerTransportFactory(commandDetails);
		const sourceAcceptedEvent = makeSourceAcceptedMetadataEvent(
			makeSourceIdentity({ subscriptionGeneration: 7 }),
		);
		registerDisposer(installBridgeReadyHandshake({ pushNonce: 'push-1' }).dispose);
		vi.spyOn(globalThis, 'fetch').mockImplementation(async (input, init): Promise<Response> => {
			return (
				recordBridgeSchemeRPCFetch(input, init, commandDetails) ??
				new Response('unexpected request', { status: 404 })
			);
		});
		const productSession: BridgeFileViewerBrowserTestProductSession = {
			initialMetadataEvents: [sourceAcceptedEvent],
			onMetadataSubscription: (publisher): void => {
				publishMetadataEvents = publisher;
			},
		};

		renderFileProductApp(
			<BridgeApp reviewWorkerTransportFactory={reviewWorkerTransportFactory} viewerMode="file" />,
			productSession,
		);
		expect(
			await pollWithinActUntilEqual(
				() => activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource).length,
				1,
			),
		).toBe(1);

		await actUpdate((): void => {
			requireMetadataPublisher(publishMetadataEvents)([sourceAcceptedEvent]);
		});
		expect(
			await pollWithinActUntilEqual(
				() => activeViewerModeUpdates(commandDetails).filter(hasWorktreeFileActiveSource).length,
				1,
			),
		).toBe(1);
	});

	test('parses document protocol metadata with Review as the fail-closed fallback', () => {
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('review');
		document.documentElement.setAttribute('data-bridge-app-protocol', 'worktree-file');
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('worktree-file');
		document.documentElement.setAttribute('data-bridge-app-protocol', 'review-package');
		expect(resolveBridgeAppProtocolFromElement(document.documentElement)).toBe('review');
	});
});

function assertSharedResizableRailFallbackGeometry(props: {
	readonly contentPanelTestId: string;
	readonly frameTestId: string;
	readonly handleId: string;
	readonly railPanelTestId: string;
}): void {
	const frame = requireHTMLElement(document.querySelector(`[data-testid="${props.frameTestId}"]`));
	const layout = requireHTMLElement(frame.querySelector('[data-slot="resizable-panel-group"]'));
	const contentPanel = requireHTMLElement(
		frame.querySelector(`[data-testid="${props.contentPanelTestId}"]`),
	);
	const resizeHandle = requireHTMLElement(frame.querySelector(`#${props.handleId}`));
	const railPanel = requireHTMLElement(
		frame.querySelector(`[data-testid="${props.railPanelTestId}"]`),
	);
	const layoutBox = layout.getBoundingClientRect();
	const contentBox = contentPanel.getBoundingClientRect();
	const handleBox = resizeHandle.getBoundingClientRect();
	const railBox = railPanel.getBoundingClientRect();

	expect(layout.getAttribute('data-panel-group-direction')).toBe('horizontal');
	expect(contentPanel.id).toBe(props.contentPanelTestId);
	expect(railPanel.id).toBe(props.railPanelTestId);
	expect(layoutBox.width).toBeGreaterThan(700);
	expect(contentBox.width).toBeGreaterThan(railBox.width);
	expect(handleBox.width).toBeGreaterThanOrEqual(1);
	expect(railBox.width).toBeGreaterThanOrEqual(240);
	expect(railBox.height).toBeGreaterThan(200);
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) {
		throw new Error('Expected Bridge app browser test element to be an HTMLElement');
	}
	return element;
}

function requireActiveContextButton(mode: 'file' | 'review'): HTMLElement {
	return requireHTMLElement(
		document.querySelector(
			`[data-bridge-viewer-mode-active="true"] [data-testid="bridge-viewer-context-${mode}"]`,
		),
	);
}

function renderFileProductApp(
	app: ReactElement,
	productSession: BridgeFileViewerBrowserTestProductSession,
): ReturnType<typeof render> {
	const transportFactory = createBridgeFileViewerBrowserTestCommWorkerTransportFactory({
		productSessionRef: { current: productSession },
	});
	return render(
		<BridgeFileViewerRuntimeTransportFactoryProvider transportFactory={transportFactory}>
			{app}
		</BridgeFileViewerRuntimeTransportFactoryProvider>,
	);
}

function activeFileProductSession(): BridgeFileViewerBrowserTestProductSession {
	return {
		initialMetadataEvents: [
			makeSourceAcceptedMetadataEvent(makeSourceIdentity({ subscriptionGeneration: 7 })),
		],
	};
}

function createRecordingBridgeWorkerTransportFactory(
	commandDetails: BridgeRPCCommand[],
	onCommand?: (command: BridgeRPCCommand) => void | Promise<void>,
): InProcessBridgeReviewWorkerTransportFactory {
	return createInProcessBridgeReviewWorkerTransportFactory({
		sendSchemeRpcCommand: async (command): Promise<unknown> => {
			commandDetails.push(command);
			await onCommand?.(command);
			return {};
		},
	});
}

function availableFileSource(): ReturnType<
	NonNullable<BridgeFileViewerBrowserTestProductSession['currentSource']>
> {
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

function requireMetadataPublisher(
	publisher: PublishFileMetadataEvents | null,
): PublishFileMetadataEvents {
	if (publisher === null) {
		throw new Error('Expected typed File metadata subscription publisher.');
	}
	return publisher;
}

function activeViewerModeUpdates(
	commandDetails: readonly BridgeRPCCommand[],
): ActiveViewerModeUpdateDetail[] {
	return commandDetails.filter(isActiveViewerModeUpdate);
}

function isActiveViewerModeUpdate(value: unknown): value is ActiveViewerModeUpdateDetail {
	return (
		isRecord(value) &&
		value['method'] === 'bridge.activeViewerMode.update' &&
		isRecord(value['params']) &&
		(value['params']['mode'] === 'file' || value['params']['mode'] === 'review') &&
		typeof value['params']['sequence'] === 'number' &&
		typeof value['params']['sessionId'] === 'string'
	);
}

function hasWorktreeFileActiveSource(detail: ActiveViewerModeUpdateDetail): boolean {
	return (
		detail.params.mode === 'file' &&
		isRecord(detail.params.activeSource) &&
		detail.params.activeSource['protocol'] === 'worktree-file' &&
		detail.params.activeSource['streamId'] === 'dev-worktree-source' &&
		detail.params.activeSource['generation'] === 7
	);
}

function isWorktreeFileActiveViewerModeCommand(message: BridgeWorkerMainToServerMessage): boolean {
	return (
		message.command === 'activeViewerModeUpdate' &&
		message.update.mode === 'file' &&
		isRecord(message.update.activeSource) &&
		message.update.activeSource['protocol'] === 'worktree-file' &&
		message.update.activeSource['streamId'] === 'dev-worktree-source' &&
		message.update.activeSource['generation'] === 7
	);
}

function hasReviewActiveSource(detail: ActiveViewerModeUpdateDetail): boolean {
	return (
		detail.params.mode === 'review' &&
		isRecord(detail.params.activeSource) &&
		detail.params.activeSource['protocol'] === 'review' &&
		detail.params.activeSource['streamId'] === 'review:bridge-app-test-pane' &&
		detail.params.activeSource['generation'] === 1
	);
}

function activeViewerMode(): string | null {
	return (
		document
			.querySelector('[data-testid="bridge-app-root"]')
			?.getAttribute('data-bridge-viewer-mode') ?? null
	);
}

async function dispatchIntakeFrame(
	frame: BridgeIntakeFrame & { readonly nonce: string },
): Promise<void> {
	await actUpdate((): void => {
		document.dispatchEvent(
			new CustomEvent('__bridge_intake_json', {
				detail: {
					nonce: frame.nonce,
					json: JSON.stringify(frame),
				},
			}),
		);
	});
}

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null;
}
