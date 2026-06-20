import type { ReactElement } from 'react';
import { useCallback, useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { useStore } from 'zustand';

import {
	type BridgePageHandshakeSession,
	installBridgePageHandshakeSession,
} from '../bridge/bridge-page-handshake.js';
import type { BridgePushEnvelope } from '../bridge/bridge-push-envelope.js';
import {
	type BridgePushDropReason,
	installBridgePushReceiver,
} from '../bridge/bridge-push-receiver.js';
import { createBridgeRPCClient } from '../bridge/bridge-rpc-client.js';
import { createBridgeTelemetryEventSink } from '../bridge/bridge-telemetry-event-sink.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import type { BridgeReviewDelta } from '../foundation/review-package/bridge-review-delta.js';
import {
	applyDeltaToBridgeReviewItemRegistry,
	createBridgeReviewItemRegistry,
} from '../foundation/review-package/bridge-review-item-registry.js';
import {
	bridgeReviewDeltaSchema,
	bridgeReviewPackageSchema,
} from '../foundation/review-package/bridge-review-package-schema.js';
import type {
	BridgeReviewItemDescriptor,
	BridgeReviewPackage,
} from '../foundation/review-package/bridge-review-package.js';
import {
	createBridgeTelemetryRecorder,
	type BridgeTelemetryRecorder,
} from '../foundation/telemetry/bridge-telemetry-recorder.js';
import {
	planeForBridgeTelemetrySlice,
	priorityForBridgeTelemetrySlice,
	type BridgeTelemetrySlice,
} from '../foundation/telemetry/bridge-telemetry-taxonomy.js';
import {
	createBridgeChildTraceContext,
	type BridgeTraceContext,
} from '../foundation/telemetry/bridge-trace-context.js';
import type { BridgeCodeViewContentResources } from '../review-viewer/code-view/bridge-code-view-materialization.js';
import {
	bridgeMarkdownPreviewMaxBytes,
	resolveBridgeMarkdownPreviewDecision,
	type BridgeMarkdownPreviewFallbackReason,
} from '../review-viewer/markdown/bridge-markdown-render-mode.js';
import type { BridgeReviewProjectionResult } from '../review-viewer/models/review-projection-models.js';
import {
	loadReviewItemContentResources,
	loadSelectedReviewItemContentResources,
} from '../review-viewer/runtime/review-content-loader.js';
import { useBridgeReviewProjectionCoordinator } from '../review-viewer/runtime/use-review-projection-coordinator.js';
import {
	BridgeReviewEmptyShell,
	BridgeReviewProjectionFailedShell,
	BridgeReviewProjectionPendingShell,
	ReviewViewerShell,
} from '../review-viewer/shell/review-viewer-shell.js';
import {
	createBridgeReviewViewerStore,
	selectBridgeReviewViewerRootSnapshot,
	type BridgeReviewViewerStore,
	type BridgeReviewViewerRootSnapshot,
	type BridgeReviewViewerStoreActions,
} from '../review-viewer/state/review-viewer-store.js';
import { recordBridgeViewerContentQueueTelemetry } from '../review-viewer/telemetry/bridge-review-viewer-telemetry.js';
import type {
	BridgeMarkdownRenderWorkerClient,
	BridgeMarkdownRenderWorkerClientCompletion,
} from '../review-viewer/workers/markdown/bridge-markdown-render-worker-client.js';
import { createBridgeMarkdownRenderWebWorkerClient } from '../review-viewer/workers/markdown/bridge-markdown-render-worker-transport.js';
import type { BridgeReviewProjectionWorkerClient } from '../review-viewer/workers/rpc/review-projection-worker-client.js';
import { createBridgeReviewProjectionWebWorkerClient } from '../review-viewer/workers/rpc/review-projection-worker-transport.js';
import {
	bridgeAppControlCommandSchema,
	type BridgeAppControlCommand,
	type BridgeAppControlProbe,
} from './bridge-app-control.js';

export interface BridgeAppProps {
	readonly target?: EventTarget;
	readonly fetchContent?: BridgeContentFetch;
	readonly projectionWorkerClient?: BridgeReviewProjectionWorkerClient;
	readonly markdownWorkerClient?: BridgeMarkdownRenderWorkerClient | null;
	readonly codeViewWorkerPoolEnabled?: boolean;
	readonly codeViewWorkerFactory?: () => Worker;
}

declare global {
	interface Window {
		bridgeReviewControlProbe?: BridgeAppControlProbe;
	}
}

interface BridgeReviewPackageTelemetryContext {
	readonly slice: BridgeTelemetrySlice;
	readonly traceContext: BridgeTraceContext | null;
}

interface SelectedContentResourcesState {
	readonly itemId: string;
	readonly contentKey: string;
	readonly status: 'loading' | 'ready' | 'failed';
	readonly resources: BridgeCodeViewContentResources | null;
}

interface SelectedMarkdownPreviewState {
	readonly itemId: string;
	readonly contentKey: string;
	readonly sourcePath: string;
	readonly status: 'rendering' | 'ready' | 'failed';
	readonly html: string | null;
}

const bridgeMarkdownPreviewAbortKey = 'bridge-review-markdown-preview';

type MarkdownPreviewFallbackTelemetryReason =
	| BridgeMarkdownPreviewFallbackReason
	| 'workerUnavailable';

function useBridgeReviewViewerStore(): BridgeReviewViewerStore {
	const storeRef = useRef<BridgeReviewViewerStore | null>(null);
	if (storeRef.current === null) {
		storeRef.current = createBridgeReviewViewerStore();
	}
	return storeRef.current;
}

export function BridgeApp(props: BridgeAppProps = {}): ReactElement {
	const target = props.target ?? document;
	const viewerStore = useBridgeReviewViewerStore();
	const projection = useStore(viewerStore, (state) => state.projection);
	const rootSnapshot = useStore(viewerStore, selectBridgeReviewViewerRootSnapshot);
	const viewerActions = useStore(viewerStore, (state) => state.actions);
	const [reviewPackage, setReviewPackage] = useState<BridgeReviewPackage | null>(null);
	const [selectedContentResourcesState, setSelectedContentResourcesState] =
		useState<SelectedContentResourcesState | null>(null);
	const [selectedMarkdownPreviewState, setSelectedMarkdownPreviewState] =
		useState<SelectedMarkdownPreviewState | null>(null);
	const [codeViewRenderedItemIds, setCodeViewRenderedItemIds] = useState<readonly string[]>([]);
	const [isTreeSearchOpen, setIsTreeSearchOpen] = useState(false);
	const [codeViewContentResourcesByItemId, setCodeViewContentResourcesByItemId] = useState<
		ReadonlyMap<string, BridgeCodeViewContentResources>
	>(() => new Map<string, BridgeCodeViewContentResources>());
	const telemetryRecorderRef = useRef<BridgeTelemetryRecorder>(createBridgeTelemetryRecorder(null));
	const currentReviewPackageTelemetryContextRef =
		useRef<BridgeReviewPackageTelemetryContext | null>(null);
	const reviewPackageTelemetryContextRef = useRef<Map<string, BridgeReviewPackageTelemetryContext>>(
		new Map(),
	);
	const lastTelemetryMarkedItemRef = useRef<string | null>(null);
	const lastFirstRenderPackageRef = useRef<string | null>(null);
	const codeViewContentResourceKeysByItemIdRef = useRef<Map<string, string>>(new Map());
	const codeViewContentInFlightKeysRef = useRef<Set<string>>(new Set());
	const reviewPackageRef = useRef<BridgeReviewPackage | null>(null);
	reviewPackageRef.current = reviewPackage;
	const projectionRef = useRef(projection);
	projectionRef.current = projection;
	const rootSnapshotRef = useRef(rootSnapshot);
	rootSnapshotRef.current = rootSnapshot;
	const controlProbeSequenceRef = useRef(0);
	const rpcClient = useMemo(
		() =>
			createBridgeRPCClient({
				target,
				getTraceContext: (): BridgeTraceContext | null =>
					telemetryRecorderRef.current.isEnabled('web')
						? createChildTraceContext(
								currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
							)
						: null,
				telemetryRecorder: {
					isEnabled: (scope) => telemetryRecorderRef.current.isEnabled(scope),
					record: (sample) => telemetryRecorderRef.current.record(sample),
					measure: (measureProps) => telemetryRecorderRef.current.measure(measureProps),
					flush: (flushProps) => telemetryRecorderRef.current.flush(flushProps),
				},
			}),
		[target],
	);
	const defaultProjectionWorkerClient = useMemo(
		() => createBridgeReviewProjectionWebWorkerClient(),
		[],
	);
	const projectionWorkerClient = props.projectionWorkerClient ?? defaultProjectionWorkerClient;
	const defaultMarkdownWorkerClient = useMemo(
		() => createBridgeMarkdownRenderWebWorkerClient(),
		[],
	);
	const markdownWorkerClient =
		props.markdownWorkerClient === undefined
			? defaultMarkdownWorkerClient
			: props.markdownWorkerClient;
	const selectedContentResources = useMemo(
		(): BridgeCodeViewContentResources | null =>
			selectedContentResourcesForCurrentSelection({
				reviewPackage,
				selectedItemId: rootSnapshot.selectedItemId,
				selectedContentResourcesState,
			}),
		[reviewPackage, rootSnapshot.selectedItemId, selectedContentResourcesState],
	);
	const flushTelemetry = useCallback((): void => {
		telemetryRecorderRef.current.flush();
	}, []);
	const selectReviewItem = useCallback(
		(itemId: string): boolean => {
			const currentReviewPackage = reviewPackageRef.current;
			if (currentReviewPackage === null || !(itemId in currentReviewPackage.itemsById)) {
				return false;
			}
			viewerActions.setSelectedItemId(itemId);
			viewerActions.setRenderMode({ kind: 'codeView' });
			setSelectedContentResourcesState(null);
			lastTelemetryMarkedItemRef.current = makeTelemetryMarkedItemKey(currentReviewPackage, itemId);
			rpcClient.sendCommand({
				method: 'review.markFileViewed',
				params: { fileId: itemId },
			});
			return true;
		},
		[rpcClient, viewerActions],
	);
	const handleRenderedCodeViewItemIdsChange = useCallback((itemIds: readonly string[]): void => {
		setCodeViewRenderedItemIds((currentItemIds: readonly string[]): readonly string[] =>
			areStringArraysEqual(currentItemIds, itemIds) ? currentItemIds : itemIds,
		);
	}, []);

	useBridgeReviewProjectionCoordinator({
		store: viewerStore,
		reviewPackage,
		projectionMode: rootSnapshot.projectionMode,
		gitStatusFilter: rootSnapshot.gitStatusFilter,
		fileClassFilter: rootSnapshot.fileClassFilter,
		projectionWorkerClient,
		telemetryRecorder: telemetryRecorderRef.current,
		telemetryParentTraceContext:
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
		flushTelemetry,
	});

	useEffect((): (() => void) => {
		let handshakeSession: BridgePageHandshakeSession | null = null;
		const configureTelemetryRecorder = (): void => {
			const telemetryConfig = handshakeSession?.getTelemetryConfig() ?? null;
			telemetryRecorderRef.current = createBridgeTelemetryRecorder(
				telemetryConfig,
				createBridgeTelemetryEventSink({
					rpcClient,
					methodName: telemetryConfig?.rpcMethodName ?? 'system.bridgeTelemetry',
				}),
			);
		};
		const uninstallPushReceiver = installBridgePushReceiver({
			target,
			getPushNonce: (): string | null => handshakeSession?.getPushNonce() ?? null,
			onEnvelope: (envelope: BridgePushEnvelope): void => {
				recordPackageApplyTelemetry(telemetryRecorderRef.current, envelope);
				applyReviewEnvelope(
					envelope,
					setReviewPackage,
					(itemId: string | null): void => viewerActions.setSelectedItemId(itemId),
					(): string | null => viewerStore.getState().rootSnapshot.selectedItemId,
					reviewPackageRef,
					reviewPackageTelemetryContextRef.current,
					currentReviewPackageTelemetryContextRef,
				);
			},
			onDroppedEnvelope: (reason: BridgePushDropReason): void => {
				recordPushDropTelemetry(telemetryRecorderRef.current, reason);
			},
		});
		handshakeSession = installBridgePageHandshakeSession(target, {
			onTelemetryConfig: configureTelemetryRecorder,
		});
		configureTelemetryRecorder();
		return (): void => {
			uninstallPushReceiver();
			handshakeSession?.uninstall();
		};
	}, [rpcClient, target, viewerActions, viewerStore]);

	useLayoutEffect((): (() => void) => {
		const handleSelectReviewItem = (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			if (!isRecord(detail) || typeof detail['itemId'] !== 'string') {
				return;
			}
			selectReviewItem(detail['itemId']);
		};
		const windowTarget = typeof window === 'undefined' ? null : window;
		target.addEventListener('__bridge_select_review_item', handleSelectReviewItem);
		if (windowTarget !== null && windowTarget !== target) {
			windowTarget.addEventListener('__bridge_select_review_item', handleSelectReviewItem);
		}
		return (): void => {
			target.removeEventListener('__bridge_select_review_item', handleSelectReviewItem);
			if (windowTarget !== null && windowTarget !== target) {
				windowTarget.removeEventListener('__bridge_select_review_item', handleSelectReviewItem);
			}
		};
	}, [selectReviewItem, target]);

	useLayoutEffect((): (() => void) => {
		const handleBridgeAppControl = (event: Event): void => {
			const detail = 'detail' in event ? event.detail : null;
			const parsedCommand = bridgeAppControlCommandSchema.safeParse(detail);
			if (!parsedCommand.success) {
				publishBridgeAppControlProbe({
					probe: makeBridgeAppControlProbe({
						command: { method: 'bridge.fileTree.search', searchText: '' },
						status: 'rejected',
						reason: 'invalid_control_command',
						sequence: nextBridgeAppControlProbeSequence(controlProbeSequenceRef),
						rootSnapshot: rootSnapshotRef.current,
					}),
				});
				return;
			}
			const result = applyBridgeAppControlCommand({
				command: parsedCommand.data,
				markdownWorkerClient,
				projection: projectionRef.current,
				rootSnapshot: rootSnapshotRef.current,
				reviewPackage: reviewPackageRef.current,
				selectReviewItem,
				selectedContentResources,
				setTreeSearchOpen: setIsTreeSearchOpen,
				viewerActions,
			});
			publishBridgeAppControlProbe({
				probe: makeBridgeAppControlProbe({
					command: parsedCommand.data,
					status: result.status,
					reason: result.reason,
					sequence: nextBridgeAppControlProbeSequence(controlProbeSequenceRef),
					rootSnapshot: viewerStore.getState().rootSnapshot,
				}),
			});
		};
		const windowTarget = typeof window === 'undefined' ? null : window;
		target.addEventListener('__bridge_review_control', handleBridgeAppControl);
		if (windowTarget !== null && windowTarget !== target) {
			windowTarget.addEventListener('__bridge_review_control', handleBridgeAppControl);
		}
		return (): void => {
			target.removeEventListener('__bridge_review_control', handleBridgeAppControl);
			if (windowTarget !== null && windowTarget !== target) {
				windowTarget.removeEventListener('__bridge_review_control', handleBridgeAppControl);
			}
		};
	}, [
		markdownWorkerClient,
		selectReviewItem,
		selectedContentResources,
		target,
		viewerActions,
		viewerStore,
	]);

	useEffect((): (() => void) => {
		let didCancel = false;
		const contentAbortController = new AbortController();
		const selectedItemId = rootSnapshot.selectedItemId;
		if (reviewPackage === null || selectedItemId === null) {
			setSelectedContentResourcesState(null);
			return (): void => {
				didCancel = true;
				contentAbortController.abort();
			};
		}
		const selectedItem = reviewPackage.itemsById[selectedItemId];
		if (selectedItem === undefined) {
			setSelectedContentResourcesState(null);
			return (): void => {
				didCancel = true;
				contentAbortController.abort();
			};
		}
		const selectedContentKey = makeSelectedContentResourcesKey(reviewPackage, selectedItemId);
		setSelectedContentResourcesState(
			(current: SelectedContentResourcesState | null): SelectedContentResourcesState | null =>
				current?.contentKey === selectedContentKey
					? current
					: {
							itemId: selectedItemId,
							contentKey: selectedContentKey,
							status: 'loading',
							resources: null,
						},
		);
		const parentTraceContext =
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null;
		recordBridgeViewerContentQueueTelemetry({
			telemetryRecorder: telemetryRecorderRef.current,
			parentTraceContext,
			item: selectedItem,
		});
		const loadProps =
			props.fetchContent === undefined
				? {
						reviewPackage,
						selectedItemId,
						traceContext: telemetryRecorderRef.current.isEnabled('web')
							? createChildTraceContext(parentTraceContext)
							: null,
						signal: contentAbortController.signal,
						telemetryRecorder: telemetryRecorderRef.current,
					}
				: {
						reviewPackage,
						selectedItemId,
						fetchContent: props.fetchContent,
						traceContext: telemetryRecorderRef.current.isEnabled('web')
							? createChildTraceContext(parentTraceContext)
							: null,
						signal: contentAbortController.signal,
						telemetryRecorder: telemetryRecorderRef.current,
					};
		void loadSelectedReviewItemContentResources(loadProps)
			.then((contentResources): void => {
				if (!didCancel) {
					setCodeViewContentResourcesByItemId(
						(
							currentResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>,
						): ReadonlyMap<string, BridgeCodeViewContentResources> => {
							const nextResourcesByItemId = new Map(currentResourcesByItemId);
							nextResourcesByItemId.set(selectedItemId, contentResources ?? {});
							codeViewContentResourceKeysByItemIdRef.current.set(
								selectedItemId,
								selectedContentKey,
							);
							return nextResourcesByItemId;
						},
					);
					setSelectedContentResourcesState({
						itemId: selectedItemId,
						contentKey: selectedContentKey,
						status: 'ready',
						resources: contentResources,
					});
				}
			})
			.catch((): void => {
				if (!didCancel) {
					setSelectedContentResourcesState({
						itemId: selectedItemId,
						contentKey: selectedContentKey,
						status: 'failed',
						resources: null,
					});
				}
			});
		return (): void => {
			didCancel = true;
			contentAbortController.abort();
		};
	}, [props.fetchContent, reviewPackage, rootSnapshot.selectedItemId]);

	useEffect((): void => {
		codeViewContentResourceKeysByItemIdRef.current.clear();
		codeViewContentInFlightKeysRef.current.clear();
		setCodeViewRenderedItemIds([]);
		setCodeViewContentResourcesByItemId(new Map<string, BridgeCodeViewContentResources>());
	}, [reviewPackage?.packageId, reviewPackage?.reviewGeneration, reviewPackage?.revision]);

	useEffect((): void => {
		if (reviewPackage === null || codeViewRenderedItemIds.length === 0) {
			return;
		}
		const parentTraceContext =
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null;
		const packageKey = makeVisibleContentPackageKey(reviewPackage);
		const pendingItemIds = uniqueStrings(codeViewRenderedItemIds)
			.filter((itemId: string): boolean => {
				const item = reviewPackage.itemsById[itemId];
				if (item === undefined || !reviewItemShouldAutoHydrateWhenRendered(item)) {
					return false;
				}
				const contentKey = makeSelectedContentResourcesKey(reviewPackage, itemId);
				return (
					codeViewContentResourceKeysByItemIdRef.current.get(itemId) !== contentKey &&
					!codeViewContentInFlightKeysRef.current.has(contentKey)
				);
			})
			.slice(0, 16);
		for (const itemId of pendingItemIds) {
			const contentKey = makeSelectedContentResourcesKey(reviewPackage, itemId);
			codeViewContentInFlightKeysRef.current.add(contentKey);
			const loadProps =
				props.fetchContent === undefined
					? {
							reviewPackage,
							itemId,
							traceContext: telemetryRecorderRef.current.isEnabled('web')
								? createChildTraceContext(parentTraceContext)
								: null,
							telemetryRecorder: telemetryRecorderRef.current,
						}
					: {
							reviewPackage,
							itemId,
							fetchContent: props.fetchContent,
							traceContext: telemetryRecorderRef.current.isEnabled('web')
								? createChildTraceContext(parentTraceContext)
								: null,
							telemetryRecorder: telemetryRecorderRef.current,
						};
			void loadReviewItemContentResources(loadProps)
				.then((contentResources): void => {
					codeViewContentInFlightKeysRef.current.delete(contentKey);
					if (
						contentResources === null ||
						reviewPackageRef.current === null ||
						makeVisibleContentPackageKey(reviewPackageRef.current) !== packageKey
					) {
						return;
					}
					codeViewContentResourceKeysByItemIdRef.current.set(itemId, contentKey);
					setCodeViewContentResourcesByItemId(
						(
							currentResourcesByItemId: ReadonlyMap<string, BridgeCodeViewContentResources>,
						): ReadonlyMap<string, BridgeCodeViewContentResources> => {
							const nextResourcesByItemId = new Map(currentResourcesByItemId);
							nextResourcesByItemId.set(itemId, contentResources);
							return nextResourcesByItemId;
						},
					);
				})
				.catch((): void => {
					codeViewContentInFlightKeysRef.current.delete(contentKey);
				});
		}
	}, [codeViewRenderedItemIds, props.fetchContent, reviewPackage]);

	useEffect((): (() => void) => {
		let didCancel = false;
		const parentTraceContext =
			currentReviewPackageTelemetryContextRef.current?.traceContext ?? null;
		if (reviewPackage === null || rootSnapshot.selectedItemId === null) {
			viewerActions.setRenderMode({ kind: 'codeView' });
			setSelectedMarkdownPreviewState(null);
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			return (): void => {
				didCancel = true;
			};
		}

		const selectedContentKey = makeSelectedContentResourcesKey(
			reviewPackage,
			rootSnapshot.selectedItemId,
		);
		const decision = resolveBridgeMarkdownPreviewDecision({
			reviewPackage,
			selectedItemId: rootSnapshot.selectedItemId,
			resources: selectedContentResources,
		});

		if (decision.kind === 'codeView') {
			viewerActions.setRenderMode({ kind: 'codeView' });
			setSelectedMarkdownPreviewState(null);
			markdownWorkerClient?.abort(bridgeMarkdownPreviewAbortKey);
			if (decision.reason !== 'contentPending') {
				recordMarkdownPreviewFallbackTelemetry({
					telemetryRecorder: telemetryRecorderRef.current,
					parentTraceContext,
					reason: decision.reason,
				});
			}
			return (): void => {
				didCancel = true;
			};
		}

		if (markdownWorkerClient === null) {
			viewerActions.setRenderMode({ kind: 'codeView' });
			setSelectedMarkdownPreviewState(null);
			recordMarkdownPreviewFallbackTelemetry({
				telemetryRecorder: telemetryRecorderRef.current,
				parentTraceContext,
				reason: 'workerUnavailable',
			});
			return (): void => {
				didCancel = true;
			};
		}

		const source = decision.source;
		const task = markdownWorkerClient.startRender({
			packageId: reviewPackage.packageId,
			reviewGeneration: reviewPackage.reviewGeneration,
			revision: reviewPackage.revision,
			itemId: source.itemId,
			itemVersion: source.itemVersion,
			contentCacheKey: source.contentCacheKey,
			contentHash: source.contentHash,
			markdownText: source.markdownText,
			sourcePath: source.sourcePath,
			abortKey: bridgeMarkdownPreviewAbortKey,
		});
		setSelectedMarkdownPreviewState({
			itemId: source.itemId,
			contentKey: selectedContentKey,
			sourcePath: source.sourcePath,
			status: 'rendering',
			html: null,
		});
		recordMarkdownRenderQueueTelemetry({
			telemetryRecorder: telemetryRecorderRef.current,
			parentTraceContext,
		});
		void task.completed.then((completion: BridgeMarkdownRenderWorkerClientCompletion): void => {
			if (didCancel) {
				return;
			}
			recordMarkdownRenderCompletionTelemetry({
				telemetryRecorder: telemetryRecorderRef.current,
				parentTraceContext,
				completion,
			});
			if (completion.status !== 'success') {
				viewerActions.setRenderMode({ kind: 'codeView' });
				setSelectedMarkdownPreviewState(null);
				return;
			}
			if (isOversizedMarkdownPreviewOutput(completion.response.html)) {
				viewerActions.setRenderMode({ kind: 'codeView' });
				setSelectedMarkdownPreviewState(null);
				return;
			}
			setSelectedMarkdownPreviewState({
				itemId: source.itemId,
				contentKey: selectedContentKey,
				sourcePath: source.sourcePath,
				status: 'ready',
				html: completion.response.html,
			});
			viewerActions.setRenderMode({ kind: 'markdownPreview' });
		});

		return (): void => {
			didCancel = true;
			markdownWorkerClient.abort(bridgeMarkdownPreviewAbortKey);
		};
	}, [
		markdownWorkerClient,
		reviewPackage,
		rootSnapshot.selectedItemId,
		selectedContentResources,
		viewerActions,
	]);

	useEffect((): void => {
		if (
			reviewPackage === null ||
			projection === null ||
			!telemetryRecorderRef.current.isEnabled('web')
		) {
			return;
		}
		const packageKey = `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}`;
		if (lastFirstRenderPackageRef.current === packageKey) {
			return;
		}
		lastFirstRenderPackageRef.current = packageKey;
		const telemetryContext = reviewPackageTelemetryContextRef.current.get(packageKey);
		telemetryRecorderRef.current.record({
			scope: 'web',
			name: 'performance.bridge.web.first_render',
			durationMilliseconds: null,
			traceContext: createChildTraceContext(telemetryContext?.traceContext ?? null),
			stringAttributes: {
				'agentstudio.bridge.phase': 'render',
				'agentstudio.bridge.plane': 'data',
				'agentstudio.bridge.priority': 'hot',
				'agentstudio.bridge.slice': telemetryContext?.slice ?? 'unknown',
				'agentstudio.bridge.transport': 'push',
			},
			numericAttributes: {},
			booleanAttributes: {},
		});
		telemetryRecorderRef.current.flush();
	}, [projection, reviewPackage]);

	useEffect((): void => {
		if (
			reviewPackage === null ||
			rootSnapshot.selectedItemId === null ||
			!telemetryRecorderRef.current.isEnabled('web')
		) {
			return;
		}
		const markedItemKey = makeTelemetryMarkedItemKey(reviewPackage, rootSnapshot.selectedItemId);
		if (lastTelemetryMarkedItemRef.current === markedItemKey) {
			return;
		}
		lastTelemetryMarkedItemRef.current = markedItemKey;
		rpcClient.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: rootSnapshot.selectedItemId },
		});
	}, [reviewPackage, rootSnapshot.selectedItemId, rpcClient]);

	const currentSelectedContentKey =
		reviewPackage !== null && rootSnapshot.selectedItemId !== null
			? makeSelectedContentResourcesKey(reviewPackage, rootSnapshot.selectedItemId)
			: null;

	return (
		<div
			className="dark h-screen min-h-screen w-full overflow-hidden bg-[var(--bridge-app-bg)] text-[var(--bridge-text-primary)] antialiased"
			data-testid="bridge-app-root"
		>
			{reviewPackage === null ? (
				<BridgeReviewEmptyShell />
			) : rootSnapshot.projectionStatus === 'failed' ? (
				<BridgeReviewProjectionFailedShell />
			) : projection === null ? (
				<BridgeReviewProjectionPendingShell />
			) : (
				<ReviewViewerShell
					codeViewContentResourcesByItemId={codeViewContentResourcesByItemId}
					fileClassFilter={rootSnapshot.fileClassFilter}
					gitStatusFilter={rootSnapshot.gitStatusFilter}
					onFileClassFilterChange={viewerActions.setFileClassFilter}
					onGitStatusFilterChange={viewerActions.setGitStatusFilter}
					onProjectionModeChange={viewerActions.setProjectionMode}
					onRenderedCodeViewItemIdsChange={handleRenderedCodeViewItemIdsChange}
					onSelectItem={selectReviewItem}
					onTreeSearchOpen={(): void => setIsTreeSearchOpen(true)}
					onTreeSearchTextChange={viewerActions.setTreeSearchText}
					projection={projection}
					projectionMode={rootSnapshot.projectionMode}
					reviewPackage={reviewPackage}
					selectedContentResources={selectedContentResources}
					selectedContentUnavailablePath={selectedContentUnavailablePathForCurrentSelection({
						reviewPackage,
						selectedItemId: rootSnapshot.selectedItemId,
						selectedContentResourcesState,
					})}
					selectedItemId={rootSnapshot.selectedItemId}
					{...(props.codeViewWorkerPoolEnabled === undefined
						? {}
						: { codeViewWorkerPoolEnabled: props.codeViewWorkerPoolEnabled })}
					{...(props.codeViewWorkerFactory === undefined
						? {}
						: { codeViewWorkerFactory: props.codeViewWorkerFactory })}
					selectedMarkdownPreviewHtml={
						rootSnapshot.renderMode.kind === 'markdownPreview' &&
						selectedMarkdownPreviewState !== null &&
						selectedMarkdownPreviewState.status === 'ready' &&
						selectedMarkdownPreviewState.itemId === rootSnapshot.selectedItemId &&
						selectedMarkdownPreviewState.contentKey === currentSelectedContentKey
							? selectedMarkdownPreviewState.html
							: null
					}
					selectedMarkdownPreviewSourcePath={
						rootSnapshot.renderMode.kind === 'markdownPreview' &&
						selectedMarkdownPreviewState !== null &&
						selectedMarkdownPreviewState.status === 'ready' &&
						selectedMarkdownPreviewState.itemId === rootSnapshot.selectedItemId &&
						selectedMarkdownPreviewState.contentKey === currentSelectedContentKey
							? selectedMarkdownPreviewState.sourcePath
							: null
					}
					telemetryParentTraceContext={
						currentReviewPackageTelemetryContextRef.current?.traceContext ?? null
					}
					telemetryRecorder={telemetryRecorderRef.current}
					treeSearchOpen={isTreeSearchOpen}
					treeSearchText={rootSnapshot.treeSearchText}
				/>
			)}
		</div>
	);
}

interface ApplyBridgeAppControlCommandProps {
	readonly command: BridgeAppControlCommand;
	readonly markdownWorkerClient: BridgeMarkdownRenderWorkerClient | null;
	readonly projection: BridgeReviewProjectionResult | null;
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectReviewItem: (itemId: string) => boolean;
	readonly selectedContentResources: BridgeCodeViewContentResources | null;
	readonly setTreeSearchOpen: (isOpen: boolean) => void;
	readonly viewerActions: BridgeReviewViewerStoreActions;
}

interface ApplyBridgeAppControlCommandResult {
	readonly status: BridgeAppControlProbe['status'];
	readonly reason: string | null;
}

interface MakeBridgeAppControlProbeProps {
	readonly command: BridgeAppControlCommand;
	readonly status: BridgeAppControlProbe['status'];
	readonly reason: string | null;
	readonly sequence: number;
	readonly rootSnapshot: BridgeReviewViewerRootSnapshot;
}

function applyBridgeAppControlCommand(
	props: ApplyBridgeAppControlCommandProps,
): ApplyBridgeAppControlCommandResult {
	const {
		command,
		markdownWorkerClient,
		projection,
		reviewPackage,
		selectReviewItem,
		selectedContentResources,
		viewerActions,
	} = props;
	switch (command.method) {
		case 'bridge.diff.scrollToFile':
			return selectReviewItem(command.itemId)
				? { status: 'accepted', reason: null }
				: { status: 'rejected', reason: 'item_not_found' };
		case 'bridge.fileTree.search':
			props.setTreeSearchOpen(true);
			viewerActions.setTreeSearchText(command.searchText);
			return { status: 'accepted', reason: null };
		case 'bridge.fileTree.setFilter':
			viewerActions.setGitStatusFilter(command.gitStatusFilter);
			viewerActions.setFileClassFilter(command.fileClassFilter);
			return { status: 'accepted', reason: null };
		case 'bridge.fileTree.revealPath': {
			const itemId = projection?.primaryItemIdByTreePath[command.path] ?? null;
			if (itemId === null) {
				return { status: 'rejected', reason: 'path_not_found' };
			}
			return selectReviewItem(itemId)
				? { status: 'accepted', reason: null }
				: { status: 'rejected', reason: 'item_not_found' };
		}
		case 'bridge.fileView.showMarkdownPreview': {
			const itemId = command.itemId ?? props.rootSnapshot.selectedItemId;
			if (itemId === null) {
				return { status: 'rejected', reason: 'item_not_selected' };
			}
			if (reviewPackage === null || !(itemId in reviewPackage.itemsById)) {
				return { status: 'rejected', reason: 'item_not_found' };
			}
			if (itemId !== props.rootSnapshot.selectedItemId) {
				return selectReviewItem(itemId)
					? { status: 'pending', reason: 'preview_selection_pending' }
					: { status: 'rejected', reason: 'item_not_found' };
			}
			const decision = resolveBridgeMarkdownPreviewDecision({
				reviewPackage,
				selectedItemId: itemId,
				resources: selectedContentResources,
			});
			if (decision.kind === 'codeView') {
				return decision.reason === 'contentPending'
					? { status: 'pending', reason: 'preview_content_pending' }
					: { status: 'rejected', reason: decision.reason };
			}
			if (markdownWorkerClient === null) {
				return { status: 'rejected', reason: 'worker_unavailable' };
			}
			return props.rootSnapshot.renderMode.kind === 'markdownPreview'
				? { status: 'accepted', reason: null }
				: { status: 'pending', reason: 'preview_render_pending' };
		}
	}
	return { status: 'rejected', reason: 'unsupported_method' };
}

function makeBridgeAppControlProbe(props: MakeBridgeAppControlProbeProps): BridgeAppControlProbe {
	const path = props.command.method === 'bridge.fileTree.revealPath' ? props.command.path : null;
	const itemId =
		props.command.method === 'bridge.diff.scrollToFile' ||
		props.command.method === 'bridge.fileView.showMarkdownPreview'
			? (props.command.itemId ?? props.rootSnapshot.selectedItemId)
			: props.rootSnapshot.selectedItemId;
	return {
		sequence: props.sequence,
		method: props.command.method,
		status: props.status,
		itemId,
		path,
		treeSearchText: props.rootSnapshot.treeSearchText,
		gitStatusFilter: props.rootSnapshot.gitStatusFilter,
		fileClassFilter: props.rootSnapshot.fileClassFilter,
		renderMode: props.rootSnapshot.renderMode,
		reason: props.reason,
	};
}

function publishBridgeAppControlProbe(props: { readonly probe: BridgeAppControlProbe }): void {
	if (typeof window === 'undefined') {
		return;
	}
	window.bridgeReviewControlProbe = props.probe;
}

function nextBridgeAppControlProbeSequence(ref: { current: number }): number {
	ref.current += 1;
	return ref.current;
}

function createChildTraceContext(parent: BridgeTraceContext | null): BridgeTraceContext | null {
	return parent === null ? null : createBridgeChildTraceContext(parent);
}

function makeTelemetryMarkedItemKey(reviewPackage: BridgeReviewPackage, itemId: string): string {
	return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}:${itemId}`;
}

function makeTelemetryPackageKey(reviewPackage: BridgeReviewPackage): string {
	return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}`;
}

function makeVisibleContentPackageKey(reviewPackage: BridgeReviewPackage): string {
	return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}:${reviewPackage.revision}`;
}

function makeSelectedContentResourcesKey(
	reviewPackage: BridgeReviewPackage,
	selectedItemId: string,
): string {
	const selectedItem = reviewPackage.itemsById[selectedItemId];
	if (selectedItem === undefined) {
		return `${reviewPackage.packageId}:${reviewPackage.reviewGeneration}:${reviewPackage.revision}:${selectedItemId}:missing`;
	}
	const roleKeys = [
		selectedItem.contentRoles.base,
		selectedItem.contentRoles.head,
		selectedItem.contentRoles.diff,
		selectedItem.contentRoles.file,
	]
		.map((handle): string => handle?.cacheKey ?? 'none')
		.join('|');
	return [
		reviewPackage.packageId,
		String(reviewPackage.reviewGeneration),
		String(reviewPackage.revision),
		selectedItem.itemId,
		String(selectedItem.itemVersion),
		selectedItem.cacheKey,
		roleKeys,
	].join(':');
}

function reviewItemShouldAutoHydrateWhenRendered(item: BridgeReviewItemDescriptor): boolean {
	return (
		item.changeKind === 'added' &&
		(item.contentRoles.base !== null ||
			item.contentRoles.head !== null ||
			item.contentRoles.diff !== null ||
			item.contentRoles.file !== null)
	);
}

function uniqueStrings(values: readonly string[]): readonly string[] {
	return [...new Set(values)];
}

function areStringArraysEqual(left: readonly string[], right: readonly string[]): boolean {
	if (left.length !== right.length) {
		return false;
	}
	return left.every((value: string, index: number): boolean => value === right[index]);
}

interface SelectedContentResourcesForCurrentSelectionProps {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
}

function selectedContentResourcesForCurrentSelection(
	props: SelectedContentResourcesForCurrentSelectionProps,
): BridgeCodeViewContentResources | null {
	if (props.reviewPackage === null || props.selectedItemId === null) {
		return null;
	}
	if (
		props.selectedContentResourcesState === null ||
		props.selectedContentResourcesState.itemId !== props.selectedItemId ||
		props.selectedContentResourcesState.status !== 'ready'
	) {
		return null;
	}
	const selectedContentKey = makeSelectedContentResourcesKey(
		props.reviewPackage,
		props.selectedItemId,
	);
	return props.selectedContentResourcesState.contentKey === selectedContentKey
		? props.selectedContentResourcesState.resources
		: null;
}

interface SelectedContentUnavailablePathForCurrentSelectionProps {
	readonly reviewPackage: BridgeReviewPackage | null;
	readonly selectedItemId: string | null;
	readonly selectedContentResourcesState: SelectedContentResourcesState | null;
}

function selectedContentUnavailablePathForCurrentSelection(
	props: SelectedContentUnavailablePathForCurrentSelectionProps,
): string | null {
	if (props.reviewPackage === null || props.selectedItemId === null) {
		return null;
	}
	const selectedContentKey = makeSelectedContentResourcesKey(
		props.reviewPackage,
		props.selectedItemId,
	);
	if (
		props.selectedContentResourcesState === null ||
		props.selectedContentResourcesState.itemId !== props.selectedItemId ||
		props.selectedContentResourcesState.contentKey !== selectedContentKey ||
		props.selectedContentResourcesState.status !== 'failed'
	) {
		return null;
	}
	const selectedItem = props.reviewPackage.itemsById[props.selectedItemId];
	return selectedItem?.headPath ?? selectedItem?.basePath ?? props.selectedItemId;
}

interface RecordMarkdownRenderQueueTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
}

function recordMarkdownRenderQueueTelemetry(props: RecordMarkdownRenderQueueTelemetryProps): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.markdown.render_queue',
		durationMilliseconds: null,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.phase': 'markdown_queue',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': 'queued',
			'agentstudio.bridge.slice': 'markdown_preview',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
}

interface RecordMarkdownRenderCompletionTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly completion: BridgeMarkdownRenderWorkerClientCompletion;
}

function recordMarkdownRenderCompletionTelemetry(
	props: RecordMarkdownRenderCompletionTelemetryProps,
): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	const durationMilliseconds =
		props.completion.status === 'success'
			? props.completion.response.metrics.durationMilliseconds
			: null;
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.markdown.render',
		durationMilliseconds,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.content_bytes_bucket':
				props.completion.status === 'success'
					? byteCountBucket(props.completion.response.metrics.inputBytes)
					: 'unknown',
			'agentstudio.bridge.phase': 'markdown_render',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': props.completion.status,
			'agentstudio.bridge.slice': 'markdown_preview',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
		},
		numericAttributes:
			props.completion.status === 'success'
				? {
						'agentstudio.bridge.markdown.input_bytes': props.completion.response.metrics.inputBytes,
						'agentstudio.bridge.markdown.output_bytes':
							props.completion.response.metrics.outputBytes,
					}
				: {},
		booleanAttributes: {},
	});
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.worker.task',
		durationMilliseconds,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.phase': 'worker_task',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': props.completion.status,
			'agentstudio.bridge.slice': 'worker_task',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
			'agentstudio.bridge.worker.task_kind': 'markdown_render',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
	props.telemetryRecorder.flush();
}

interface RecordMarkdownPreviewFallbackTelemetryProps {
	readonly telemetryRecorder: BridgeTelemetryRecorder;
	readonly parentTraceContext: BridgeTraceContext | null;
	readonly reason: MarkdownPreviewFallbackTelemetryReason;
}

function recordMarkdownPreviewFallbackTelemetry(
	props: RecordMarkdownPreviewFallbackTelemetryProps,
): void {
	if (!props.telemetryRecorder.isEnabled('web')) {
		return;
	}
	props.telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.markdown.fallback',
		durationMilliseconds: null,
		traceContext: createChildTraceContext(props.parentTraceContext),
		stringAttributes: {
			'agentstudio.bridge.markdown.fallback_reason': props.reason,
			'agentstudio.bridge.phase': 'markdown_decision',
			'agentstudio.bridge.plane': 'data',
			'agentstudio.bridge.priority': 'warm',
			'agentstudio.bridge.result': 'fallback',
			'agentstudio.bridge.slice': 'markdown_preview',
			'agentstudio.bridge.transport': 'worker',
			'agentstudio.bridge.worker.lane': 'markdown',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
}

function isOversizedMarkdownPreviewOutput(html: string): boolean {
	return new TextEncoder().encode(html).byteLength > bridgeMarkdownPreviewMaxBytes;
}

function byteCountBucket(byteCount: number): 'empty' | 'small' | 'medium' | 'large' | 'huge' {
	if (byteCount <= 0) {
		return 'empty';
	}
	if (byteCount <= 32_768) {
		return 'small';
	}
	if (byteCount <= 512_000) {
		return 'medium';
	}
	if (byteCount <= 5_000_000) {
		return 'large';
	}
	return 'huge';
}

function recordPackageApplyTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
	envelope: BridgePushEnvelope,
): void {
	telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.package_apply',
		durationMilliseconds: null,
		traceContext: envelope.traceContext,
		stringAttributes: {
			'agentstudio.bridge.phase': 'apply',
			'agentstudio.bridge.plane': planeForBridgeTelemetrySlice(envelope.slice),
			'agentstudio.bridge.priority': priorityForBridgeTelemetrySlice(envelope.slice),
			'agentstudio.bridge.slice': envelope.slice,
			'agentstudio.bridge.transport': 'push',
		},
		numericAttributes: {},
		booleanAttributes: {},
	});
	telemetryRecorder.flush();
}

function recordPushDropTelemetry(
	telemetryRecorder: BridgeTelemetryRecorder,
	reason: BridgePushDropReason,
): void {
	telemetryRecorder.record({
		scope: 'web',
		name: 'performance.bridge.web.telemetry_drop',
		durationMilliseconds: null,
		traceContext: null,
		stringAttributes: {
			'agentstudio.bridge.phase': 'dropped',
			'agentstudio.bridge.plane': 'observability',
			'agentstudio.bridge.priority': 'best_effort',
			'agentstudio.bridge.slice': 'telemetry_drop',
			'agentstudio.bridge.telemetry.drop_reason': reason,
			'agentstudio.bridge.transport': 'rpc',
		},
		numericAttributes: {
			'agentstudio.bridge.telemetry.dropped_count': 1,
		},
		booleanAttributes: {},
	});
	telemetryRecorder.flush({ force: true });
}

function applyReviewEnvelope(
	envelope: BridgePushEnvelope,
	setReviewPackage: (
		update: (current: BridgeReviewPackage | null) => BridgeReviewPackage | null,
	) => void,
	setSelectedItemId: (itemId: string | null) => void,
	getSelectedItemId: () => string | null,
	reviewPackageRef: { current: BridgeReviewPackage | null },
	telemetryContextByPackageKey: Map<string, BridgeReviewPackageTelemetryContext>,
	currentReviewPackageTelemetryContextRef: {
		current: BridgeReviewPackageTelemetryContext | null;
	},
): void {
	if (envelope.store !== 'diff') {
		return;
	}
	const packagePayload = extractReviewPackage(envelope.data);
	if (packagePayload !== null) {
		const currentReviewPackage = reviewPackageRef.current;
		if (
			currentReviewPackage !== null &&
			isStaleReviewPackageReplacement(currentReviewPackage, packagePayload)
		) {
			return;
		}
		const telemetryContext = {
			slice: envelope.slice,
			traceContext: envelope.traceContext,
		};
		telemetryContextByPackageKey.set(makeTelemetryPackageKey(packagePayload), telemetryContext);
		currentReviewPackageTelemetryContextRef.current = telemetryContext;
		reviewPackageRef.current = packagePayload;
		setReviewPackage((): BridgeReviewPackage => packagePayload);
		const currentSelectedItemId = getSelectedItemId();
		setSelectedItemId(
			currentSelectedItemId === null || !(currentSelectedItemId in packagePayload.itemsById)
				? firstVisibleItemId(packagePayload)
				: currentSelectedItemId,
		);
		return;
	}
	const deltaPayload = extractReviewDelta(envelope.data);
	if (deltaPayload === null) {
		return;
	}
	const telemetryContext = {
		slice: envelope.slice,
		traceContext: envelope.traceContext,
	};
	const currentReviewPackage = reviewPackageRef.current;
	if (currentReviewPackage === null) {
		return;
	}
	const result = applyDeltaToBridgeReviewItemRegistry(
		createBridgeReviewItemRegistry({ reviewPackage: currentReviewPackage, selectedItemId: null }),
		deltaPayload,
	);
	if (!result.accepted) {
		return;
	}
	telemetryContextByPackageKey.set(
		makeTelemetryPackageKey(result.registry.reviewPackage),
		telemetryContext,
	);
	currentReviewPackageTelemetryContextRef.current = telemetryContext;
	reviewPackageRef.current = result.registry.reviewPackage;
	setReviewPackage((): BridgeReviewPackage => result.registry.reviewPackage);
	const currentSelectedItemId = getSelectedItemId();
	setSelectedItemId(
		currentSelectedItemId === null ||
			!(currentSelectedItemId in result.registry.reviewPackage.itemsById)
			? firstVisibleItemId(result.registry.reviewPackage)
			: currentSelectedItemId,
	);
}

function isStaleReviewPackageReplacement(
	currentReviewPackage: BridgeReviewPackage,
	nextReviewPackage: BridgeReviewPackage,
): boolean {
	if (currentReviewPackage.packageId !== nextReviewPackage.packageId) {
		return false;
	}
	if (nextReviewPackage.reviewGeneration < currentReviewPackage.reviewGeneration) {
		return true;
	}
	return (
		nextReviewPackage.reviewGeneration === currentReviewPackage.reviewGeneration &&
		nextReviewPackage.revision <= currentReviewPackage.revision
	);
}

function extractReviewPackage(data: unknown): BridgeReviewPackage | null {
	if (!isRecord(data)) {
		return null;
	}
	const packageValue = data['package'];
	const parsedPackage = bridgeReviewPackageSchema.safeParse(packageValue);
	return parsedPackage.success ? parsedPackage.data : null;
}

function extractReviewDelta(data: unknown): BridgeReviewDelta | null {
	if (!isRecord(data)) {
		return null;
	}
	const deltaValue = data['delta'];
	const parsedDelta = bridgeReviewDeltaSchema.safeParse(deltaValue);
	return parsedDelta.success ? parsedDelta.data : null;
}

function firstVisibleItemId(reviewPackage: BridgeReviewPackage): string | null {
	const registry = createBridgeReviewItemRegistry({ reviewPackage, selectedItemId: null });
	return registry.visibleItems[0]?.itemId ?? null;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}
