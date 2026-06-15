import type { ReactElement } from 'react';
import { useEffect, useMemo, useRef, useState } from 'react';

import {
	type BridgePageHandshakeSession,
	installBridgePageHandshakeSession,
} from '../bridge/bridge-page-handshake.js';
import type { BridgePushEnvelope } from '../bridge/bridge-push-envelope.js';
import { installBridgePushReceiver } from '../bridge/bridge-push-receiver.js';
import { createBridgeRPCClient } from '../bridge/bridge-rpc-client.js';
import { createBridgeTelemetryEventSink } from '../bridge/bridge-telemetry-event-sink.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import type { BridgeReviewDelta } from '../foundation/review-package/bridge-review-delta.js';
import {
	applyDeltaToBridgeReviewItemRegistry,
	createBridgeReviewItemRegistry,
} from '../foundation/review-package/bridge-review-item-registry.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
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
import {
	BridgeReviewEmptyShell,
	loadSelectedReviewItemContent,
	ReviewViewerShell,
} from '../review-viewer/shell/review-viewer-shell.js';

export interface BridgeAppProps {
	readonly target?: EventTarget;
	readonly fetchContent?: BridgeContentFetch;
}

interface BridgeReviewPackageTelemetryContext {
	readonly slice: BridgeTelemetrySlice;
	readonly traceContext: BridgeTraceContext | null;
}

export function BridgeApp(props: BridgeAppProps = {}): ReactElement {
	const target = props.target ?? document;
	const [reviewPackage, setReviewPackage] = useState<BridgeReviewPackage | null>(null);
	const [selectedItemId, setSelectedItemId] = useState<string | null>(null);
	const [selectedContentText, setSelectedContentText] = useState<string | null>(null);
	const telemetryRecorderRef = useRef<BridgeTelemetryRecorder>(createBridgeTelemetryRecorder(null));
	const currentReviewPackageTelemetryContextRef =
		useRef<BridgeReviewPackageTelemetryContext | null>(null);
	const reviewPackageTelemetryContextRef = useRef<Map<string, BridgeReviewPackageTelemetryContext>>(
		new Map(),
	);
	const lastTelemetryMarkedItemRef = useRef<string | null>(null);
	const lastFirstRenderPackageRef = useRef<string | null>(null);
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
					reviewPackageTelemetryContextRef.current,
					currentReviewPackageTelemetryContextRef,
				);
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

	useEffect((): (() => void) => {
		let didCancel = false;
		if (reviewPackage === null || selectedItemId === null) {
			setSelectedContentText(null);
			return (): void => {
				didCancel = true;
			};
		}
		const loadProps =
			props.fetchContent === undefined
				? {
						reviewPackage,
						selectedItemId,
						traceContext: telemetryRecorderRef.current.isEnabled('web')
							? createChildTraceContext(
									currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
								)
							: null,
						telemetryRecorder: telemetryRecorderRef.current,
					}
				: {
						reviewPackage,
						selectedItemId,
						fetchContent: props.fetchContent,
						traceContext: telemetryRecorderRef.current.isEnabled('web')
							? createChildTraceContext(
									currentReviewPackageTelemetryContextRef.current?.traceContext ?? null,
								)
							: null,
						telemetryRecorder: telemetryRecorderRef.current,
					};
		void loadSelectedReviewItemContent(loadProps).then((contentResource): void => {
			if (!didCancel) {
				setSelectedContentText(contentResource?.text ?? null);
			}
		});
		return (): void => {
			didCancel = true;
		};
	}, [props.fetchContent, reviewPackage, selectedItemId]);

	useEffect((): void => {
		if (reviewPackage === null || !telemetryRecorderRef.current.isEnabled('web')) {
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
	}, [reviewPackage]);

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
		<div data-testid="bridge-app-root">
			{reviewPackage === null ? (
				<BridgeReviewEmptyShell />
			) : (
				<ReviewViewerShell
					onSelectItem={(itemId: string): void => {
						setSelectedItemId(itemId);
						lastTelemetryMarkedItemRef.current = makeTelemetryMarkedItemKey(reviewPackage, itemId);
						rpcClient.sendCommand({
							method: 'review.markFileViewed',
							params: { fileId: itemId },
						});
					}}
					reviewPackage={reviewPackage}
					selectedContentText={selectedContentText}
					selectedItemId={selectedItemId}
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

function applyReviewEnvelope(
	envelope: BridgePushEnvelope,
	setReviewPackage: (
		update: (current: BridgeReviewPackage | null) => BridgeReviewPackage | null,
	) => void,
	setSelectedItemId: (update: (current: string | null) => string | null) => void,
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
