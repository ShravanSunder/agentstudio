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
import type {
	BridgeFileChangeKind,
	BridgeFileClass,
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
import type { BridgeReviewProjectionMode } from '../review-viewer/models/review-projection-models.js';
import { useBridgeReviewProjectionCoordinator } from '../review-viewer/runtime/use-review-projection-coordinator.js';
import {
	BridgeReviewEmptyShell,
	BridgeReviewProjectionPendingShell,
	loadSelectedReviewItemContentResources,
	ReviewViewerShell,
} from '../review-viewer/shell/review-viewer-shell.js';
import {
	createBridgeReviewViewerStore,
	type BridgeReviewViewerStore,
} from '../review-viewer/state/review-viewer-store.js';
import { recordBridgeViewerContentQueueTelemetry } from '../review-viewer/telemetry/bridge-review-viewer-telemetry.js';
import type { BridgeReviewProjectionWorkerClient } from '../review-viewer/workers/rpc/review-projection-worker-client.js';
import { createBridgeReviewProjectionWebWorkerClient } from '../review-viewer/workers/rpc/review-projection-worker-transport.js';

export interface BridgeAppProps {
	readonly target?: EventTarget;
	readonly fetchContent?: BridgeContentFetch;
	readonly projectionWorkerClient?: BridgeReviewProjectionWorkerClient;
}

interface BridgeReviewPackageTelemetryContext {
	readonly slice: BridgeTelemetrySlice;
	readonly traceContext: BridgeTraceContext | null;
}

interface SelectedContentResourcesState {
	readonly itemId: string;
	readonly contentKey: string;
	readonly resources: BridgeCodeViewContentResources | null;
}

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
	const [reviewPackage, setReviewPackage] = useState<BridgeReviewPackage | null>(null);
	const [selectedItemId, setSelectedItemId] = useState<string | null>(null);
	const [selectedContentResourcesState, setSelectedContentResourcesState] =
		useState<SelectedContentResourcesState | null>(null);
	const [projectionMode, setProjectionMode] = useState<BridgeReviewProjectionMode>({
		kind: 'allFiles',
	});
	const [treeSearchText, setTreeSearchText] = useState('');
	const [gitStatusFilter, setGitStatusFilter] = useState<BridgeFileChangeKind | 'all'>('all');
	const [fileClassFilter, setFileClassFilter] = useState<BridgeFileClass | 'all'>('all');
	const telemetryRecorderRef = useRef<BridgeTelemetryRecorder>(createBridgeTelemetryRecorder(null));
	const currentReviewPackageTelemetryContextRef =
		useRef<BridgeReviewPackageTelemetryContext | null>(null);
	const reviewPackageTelemetryContextRef = useRef<Map<string, BridgeReviewPackageTelemetryContext>>(
		new Map(),
	);
	const lastTelemetryMarkedItemRef = useRef<string | null>(null);
	const lastFirstRenderPackageRef = useRef<string | null>(null);
	const reviewPackageRef = useRef<BridgeReviewPackage | null>(null);
	reviewPackageRef.current = reviewPackage;
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
	const flushTelemetry = useCallback((): void => {
		telemetryRecorderRef.current.flush();
	}, []);
	const selectReviewItem = useCallback(
		(itemId: string): void => {
			const currentReviewPackage = reviewPackageRef.current;
			if (currentReviewPackage === null || !(itemId in currentReviewPackage.itemsById)) {
				return;
			}
			setSelectedItemId(itemId);
			setSelectedContentResourcesState(null);
			lastTelemetryMarkedItemRef.current = makeTelemetryMarkedItemKey(currentReviewPackage, itemId);
			rpcClient.sendCommand({
				method: 'review.markFileViewed',
				params: { fileId: itemId },
			});
		},
		[rpcClient],
	);

	useBridgeReviewProjectionCoordinator({
		store: viewerStore,
		reviewPackage,
		projectionMode,
		gitStatusFilter,
		fileClassFilter,
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
					setSelectedItemId,
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
	}, [rpcClient, target]);

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

	useEffect((): (() => void) => {
		let didCancel = false;
		const contentAbortController = new AbortController();
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
				current?.contentKey === selectedContentKey ? current : null,
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
					setSelectedContentResourcesState({
						itemId: selectedItemId,
						contentKey: selectedContentKey,
						resources: contentResources,
					});
				}
			})
			.catch((): void => {
				if (!didCancel) {
					setSelectedContentResourcesState({
						itemId: selectedItemId,
						contentKey: selectedContentKey,
						resources: null,
					});
				}
			});
		return (): void => {
			didCancel = true;
			contentAbortController.abort();
		};
	}, [props.fetchContent, reviewPackage, selectedItemId]);

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
			selectedItemId === null ||
			!telemetryRecorderRef.current.isEnabled('web')
		) {
			return;
		}
		const markedItemKey = makeTelemetryMarkedItemKey(reviewPackage, selectedItemId);
		if (lastTelemetryMarkedItemRef.current === markedItemKey) {
			return;
		}
		lastTelemetryMarkedItemRef.current = markedItemKey;
		rpcClient.sendCommand({
			method: 'review.markFileViewed',
			params: { fileId: selectedItemId },
		});
	}, [reviewPackage, rpcClient, selectedItemId]);

	return (
		<div
			className="dark h-screen min-h-screen w-full overflow-hidden bg-[var(--bridge-app-bg)] text-[var(--bridge-text-primary)] antialiased"
			data-testid="bridge-app-root"
		>
			{reviewPackage === null ? (
				<BridgeReviewEmptyShell />
			) : projection === null ? (
				<BridgeReviewProjectionPendingShell />
			) : (
				<ReviewViewerShell
					fileClassFilter={fileClassFilter}
					gitStatusFilter={gitStatusFilter}
					onFileClassFilterChange={setFileClassFilter}
					onGitStatusFilterChange={setGitStatusFilter}
					onProjectionModeChange={setProjectionMode}
					onSelectItem={selectReviewItem}
					onTreeSearchTextChange={setTreeSearchText}
					projection={projection}
					projectionMode={projectionMode}
					reviewPackage={reviewPackage}
					selectedContentResources={
						selectedContentResourcesState?.itemId === selectedItemId &&
						selectedContentResourcesState.contentKey ===
							makeSelectedContentResourcesKey(reviewPackage, selectedItemId)
							? selectedContentResourcesState.resources
							: null
					}
					selectedItemId={selectedItemId}
					telemetryParentTraceContext={
						currentReviewPackageTelemetryContextRef.current?.traceContext ?? null
					}
					telemetryRecorder={telemetryRecorderRef.current}
					treeSearchText={treeSearchText}
				/>
			)}
		</div>
	);
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
	setSelectedItemId: (update: (current: string | null) => string | null) => void,
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
		const telemetryContext = {
			slice: envelope.slice,
			traceContext: envelope.traceContext,
		};
		telemetryContextByPackageKey.set(makeTelemetryPackageKey(packagePayload), telemetryContext);
		currentReviewPackageTelemetryContextRef.current = telemetryContext;
		reviewPackageRef.current = packagePayload;
		setReviewPackage((): BridgeReviewPackage => packagePayload);
		setSelectedItemId((current: string | null): string | null =>
			current === null || !(current in packagePayload.itemsById)
				? firstVisibleItemId(packagePayload)
				: current,
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
	setReviewPackage((current: BridgeReviewPackage | null): BridgeReviewPackage | null => {
		if (current === null) {
			return null;
		}
		const result = applyDeltaToBridgeReviewItemRegistry(
			createBridgeReviewItemRegistry({ reviewPackage: current, selectedItemId: null }),
			deltaPayload,
		);
		if (!result.accepted) {
			return current;
		}
		telemetryContextByPackageKey.set(
			makeTelemetryPackageKey(result.registry.reviewPackage),
			telemetryContext,
		);
		currentReviewPackageTelemetryContextRef.current = telemetryContext;
		reviewPackageRef.current = result.registry.reviewPackage;
		setSelectedItemId((selectedItemId: string | null): string | null =>
			selectedItemId === null || !(selectedItemId in result.registry.reviewPackage.itemsById)
				? firstVisibleItemId(result.registry.reviewPackage)
				: selectedItemId,
		);
		return result.registry.reviewPackage;
	});
}

function extractReviewPackage(data: unknown): BridgeReviewPackage | null {
	if (!isRecord(data)) {
		return null;
	}
	const packageValue = data['package'];
	return isBridgeReviewPackage(packageValue) ? packageValue : null;
}

function extractReviewDelta(data: unknown): BridgeReviewDelta | null {
	if (!isRecord(data)) {
		return null;
	}
	const deltaValue = data['delta'];
	return isBridgeReviewDelta(deltaValue) ? deltaValue : null;
}

function firstVisibleItemId(reviewPackage: BridgeReviewPackage): string | null {
	const registry = createBridgeReviewItemRegistry({ reviewPackage, selectedItemId: null });
	return registry.visibleItems[0]?.itemId ?? null;
}

function isRecord(value: unknown): value is Readonly<Record<string, unknown>> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function isBridgeReviewPackage(value: unknown): value is BridgeReviewPackage {
	return (
		isRecord(value) &&
		value['schemaVersion'] === 1 &&
		typeof value['packageId'] === 'string' &&
		typeof value['reviewGeneration'] === 'number' &&
		typeof value['revision'] === 'number' &&
		Array.isArray(value['orderedItemIds']) &&
		isRecord(value['itemsById'])
	);
}

function isBridgeReviewDelta(value: unknown): value is BridgeReviewDelta {
	return (
		isRecord(value) &&
		typeof value['packageId'] === 'string' &&
		typeof value['reviewGeneration'] === 'number' &&
		typeof value['revision'] === 'number' &&
		isRecord(value['operations'])
	);
}
