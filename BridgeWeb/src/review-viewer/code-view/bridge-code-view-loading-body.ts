import type { PostRenderPhase } from '@pierre/diffs';

import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';

const bridgeCodeViewLoadingBodyTestId = 'bridge-code-view-loading-body';

export interface SyncBridgeCodeViewLoadingBodyProps {
	readonly containerElement: HTMLElement;
	readonly item: BridgeCodeViewItem;
	readonly phase: PostRenderPhase;
}

export function syncBridgeCodeViewLoadingBody(props: SyncBridgeCodeViewLoadingBodyProps): void {
	if (props.phase === 'unmount' || props.item.bridgeMetadata.contentState !== 'loading') {
		removeBridgeCodeViewLoadingBody(props.containerElement);
		return;
	}

	props.containerElement.setAttribute('data-bridge-code-view-loading-item', 'true');
	if (props.containerElement.querySelector(loadingBodySelector()) !== null) {
		return;
	}
	props.containerElement.append(createBridgeCodeViewLoadingBodyElement());
}

function removeBridgeCodeViewLoadingBody(containerElement: HTMLElement): void {
	containerElement.removeAttribute('data-bridge-code-view-loading-item');
	containerElement.querySelector(loadingBodySelector())?.remove();
}

function loadingBodySelector(): string {
	return `[data-testid="${bridgeCodeViewLoadingBodyTestId}"]`;
}

function createBridgeCodeViewLoadingBodyElement(): HTMLElement {
	const bodyElement = document.createElement('div');
	bodyElement.setAttribute('data-testid', bridgeCodeViewLoadingBodyTestId);
	bodyElement.className = [
		'pointer-events-none absolute left-16 top-12 z-10 flex w-[min(26rem,calc(100%-5rem))]',
		'flex-col gap-2 rounded-md border border-[var(--bridge-border-subtle)]',
		'bg-[var(--bridge-surface-bg)]/80 p-3 shadow-[0_18px_48px_rgb(0_0_0_/_0.45)] backdrop-blur',
	].join(' ');
	bodyElement.append(
		createSkeletonRowElement('w-full'),
		createSkeletonRowElement('w-11/12'),
		createSkeletonRowElement('w-3/4'),
	);
	return bodyElement;
}

function createSkeletonRowElement(widthClassName: string): HTMLElement {
	const rowElement = document.createElement('div');
	rowElement.setAttribute('data-slot', 'skeleton');
	rowElement.className = [
		'animate-pulse rounded-md bg-muted',
		'h-3 bg-[var(--bridge-surface-raised-bg)]',
		widthClassName,
	].join(' ');
	return rowElement;
}
