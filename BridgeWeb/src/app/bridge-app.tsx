import type { ReactElement } from 'react';
import { useEffect, useMemo, useState } from 'react';

import {
	type BridgePageHandshakeSession,
	installBridgePageHandshakeSession,
} from '../bridge/bridge-page-handshake.js';
import type { BridgePushEnvelope } from '../bridge/bridge-push-envelope.js';
import { installBridgePushReceiver } from '../bridge/bridge-push-receiver.js';
import { createBridgeRPCClient } from '../bridge/bridge-rpc-client.js';
import type { BridgeContentFetch } from '../foundation/content/content-resource-loader.js';
import type { BridgeReviewDelta } from '../foundation/review-package/bridge-review-delta.js';
import {
	applyDeltaToBridgeReviewItemRegistry,
	createBridgeReviewItemRegistry,
} from '../foundation/review-package/bridge-review-item-registry.js';
import type { BridgeReviewPackage } from '../foundation/review-package/bridge-review-package.js';
import {
	BridgeReviewEmptyShell,
	loadSelectedReviewItemContent,
	ReviewViewerShell,
} from '../review-viewer/shell/review-viewer-shell.js';

export interface BridgeAppProps {
	readonly target?: EventTarget;
	readonly fetchContent?: BridgeContentFetch;
}

export function BridgeApp(props: BridgeAppProps = {}): ReactElement {
	const target = props.target ?? document;
	const [reviewPackage, setReviewPackage] = useState<BridgeReviewPackage | null>(null);
	const [selectedItemId, setSelectedItemId] = useState<string | null>(null);
	const [selectedContentText, setSelectedContentText] = useState<string | null>(null);
	const rpcClient = useMemo(() => createBridgeRPCClient({ target }), [target]);

	useEffect((): (() => void) => {
		let handshakeSession: BridgePageHandshakeSession | null = null;
		const uninstallPushReceiver = installBridgePushReceiver({
			target,
			getPushNonce: (): string | null => handshakeSession?.getPushNonce() ?? null,
			onEnvelope: (envelope: BridgePushEnvelope): void => {
				applyReviewEnvelope(envelope, setReviewPackage, setSelectedItemId);
			},
		});
		handshakeSession = installBridgePageHandshakeSession(target);
		return (): void => {
			uninstallPushReceiver();
			handshakeSession?.uninstall();
		};
	}, [target]);

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
					}
				: {
						reviewPackage,
						selectedItemId,
						fetchContent: props.fetchContent,
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

	return (
		<div data-testid="bridge-app-root">
			{reviewPackage === null ? (
				<BridgeReviewEmptyShell />
			) : (
				<ReviewViewerShell
					onSelectItem={(itemId: string): void => {
						setSelectedItemId(itemId);
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

function applyReviewEnvelope(
	envelope: BridgePushEnvelope,
	setReviewPackage: (
		update: (current: BridgeReviewPackage | null) => BridgeReviewPackage | null,
	) => void,
	setSelectedItemId: (update: (current: string | null) => string | null) => void,
): void {
	if (envelope.store !== 'diff') {
		return;
	}
	const packagePayload = extractReviewPackage(envelope.data);
	if (packagePayload !== null) {
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
