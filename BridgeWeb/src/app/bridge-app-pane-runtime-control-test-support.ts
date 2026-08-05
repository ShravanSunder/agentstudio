import { expect } from 'vitest';

import {
	BRIDGE_WORKER_WIRE_VERSION,
	type BridgeWorkerServerToMainMessage,
} from '../core/comm-worker/bridge-worker-contracts.js';
import type { BridgeWorkerRpcCommandInput } from '../core/comm-worker/bridge-worker-rpc-client.js';
import {
	actWait,
	pollWithinActUntilEqual,
	pollWithinActUntilTruthy,
} from './bridge-app-browser-test-actions.js';
import { bridgeAppControlProbeSchema, type BridgeAppControlProbe } from './bridge-app-control.js';
import { advanceAnimationFrame } from './bridge-app-pane-runtime-position-test-support.js';

export function makeNativeSurfaceSelectionRequest(props: {
	readonly bindingRevision: number;
	readonly nativeSelectionRequestId: string;
	readonly surface: 'file' | 'review';
}): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		kind: 'nativeSurfaceSelectionRequest',
		metadataStreamId: 'metadata-stream-1',
		navigationCommand: {
			bindingRevision: props.bindingRevision,
			commandId: props.nativeSelectionRequestId,
			commandKind: 'activateContext',
			surface: props.surface,
		},
		paneSessionId: 'pane-session-1',
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		workerInstanceId: 'worker-instance-1',
	};
}

export function makeNativeFileTargetSelectionRequest(props: {
	readonly bindingRevision: number;
	readonly commandId: string;
	readonly path: string;
	readonly sourceId: string;
	readonly subscriptionGeneration: number;
}): BridgeWorkerServerToMainMessage {
	return {
		direction: 'serverWorkerToMain',
		kind: 'nativeSurfaceSelectionRequest',
		metadataStreamId: 'metadata-stream-1',
		navigationCommand: {
			bindingRevision: props.bindingRevision,
			commandId: props.commandId,
			commandKind: 'activateTarget',
			source: {
				sourceId: props.sourceId,
				sourceKind: 'file',
				subscriptionGeneration: props.subscriptionGeneration,
			},
			surface: 'file',
			target: { path: props.path, targetKind: 'file', version: 'current' },
		},
		paneSessionId: 'pane-session-1',
		transferDescriptors: [],
		wireVersion: BRIDGE_WORKER_WIRE_VERSION,
		workerInstanceId: 'worker-instance-1',
	};
}

export async function requestNativeSurface(props: {
	readonly activeViewerModeUpdateForNativeRequest: (
		nativeSelectionRequestId: string,
	) => BridgeWorkerRpcCommandInput | undefined;
	readonly appRoot: HTMLElement;
	readonly bindingRevision: number;
	readonly nativeSelectionRequestId: string;
	readonly publishNativeSurfaceSelectionRequest: (requestProps: {
		readonly bindingRevision: number;
		readonly nativeSelectionRequestId: string;
		readonly surface: 'file' | 'review';
	}) => Promise<void>;
	readonly surface: 'file' | 'review';
}): Promise<void> {
	await props.publishNativeSurfaceSelectionRequest(props);
	expect(
		await pollWithinActUntilEqual(
			() => props.appRoot.getAttribute('data-bridge-viewer-mode'),
			props.surface,
		),
	).toBe(props.surface);
	const receipt = await pollWithinActUntilTruthy(() =>
		props.activeViewerModeUpdateForNativeRequest(props.nativeSelectionRequestId),
	);
	expect(receipt).toMatchObject({
		command: 'activeViewerModeUpdate',
		update: {
			mode: props.surface,
			nativeSelectionRequestId: props.nativeSelectionRequestId,
		},
	});
}

export async function dispatchBridgeViewerFilterShortcut(): Promise<void> {
	await actWait(async (): Promise<void> => {
		document.dispatchEvent(
			new KeyboardEvent('keydown', {
				altKey: true,
				bubbles: true,
				cancelable: true,
				key: 'f',
				metaKey: true,
			}),
		);
		await Promise.resolve();
	});
}

export async function dispatchBridgePageControl(
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

export function reviewSearchInputWithin(reviewHost: HTMLElement): HTMLInputElement | null {
	const searchInput = reviewHost.querySelector('[data-testid="bridge-review-search-input"]');
	return searchInput instanceof HTMLInputElement ? searchInput : null;
}

export function fileSearchInput(): HTMLInputElement | null {
	const searchInput = document.querySelector('[data-testid="worktree-file-search-input"]');
	return searchInput instanceof HTMLInputElement ? searchInput : null;
}

export function fileTreeRowForPath(path: string): HTMLElement | null {
	const treeHost = document.querySelector(
		'[data-testid="bridge-file-viewer-pierre-file-tree"] file-tree-container',
	);
	if (!(treeHost instanceof HTMLElement) || treeHost.shadowRoot === null) return null;
	const row = treeHost.shadowRoot.querySelector(
		`[data-item-type="file"][data-item-path="${CSS.escape(path)}"]`,
	);
	return row instanceof HTMLElement ? row : null;
}

export function requireActiveContextButton(mode: 'file' | 'review'): HTMLElement {
	return requireHTMLElement(
		document.querySelector(
			`[data-bridge-viewer-mode-active="true"] [data-testid="bridge-viewer-context-${mode}"]`,
		),
	);
}

export function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected an HTML element.');
	return element;
}
