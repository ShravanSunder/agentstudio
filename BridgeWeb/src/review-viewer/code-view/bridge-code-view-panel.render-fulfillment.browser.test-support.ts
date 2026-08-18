import type { CodeView, CodeViewItem } from '@pierre/diffs';
import { expect } from 'vitest';

export interface CurrentRenderedReviewRows {
	readonly baseLines: readonly HTMLElement[];
	readonly clearHeadText: () => void;
	readonly element: HTMLElement;
	readonly headLines: readonly HTMLElement[];
	readonly shadowRoot: ShadowRoot;
}

export interface ExactItemReceiptLog<TItem, TReceipt extends { readonly contextItem: TItem }> {
	readonly receipts: TReceipt[];
	readonly record: (receipt: TReceipt) => void;
	readonly waitForItem: (item: TItem) => Promise<void>;
}

export function createExactItemReceiptLog<
	TItem,
	TReceipt extends { readonly contextItem: TItem },
>(): ExactItemReceiptLog<TItem, TReceipt> {
	const receipts: TReceipt[] = [];
	const waiters = new Map<TItem, Set<() => void>>();
	return {
		receipts,
		record: (receipt): void => {
			receipts.push(receipt);
			const matchingWaiters = waiters.get(receipt.contextItem);
			if (matchingWaiters === undefined) return;
			waiters.delete(receipt.contextItem);
			for (const resolve of matchingWaiters) resolve();
		},
		waitForItem: (item): Promise<void> => {
			if (receipts.some((receipt): boolean => receipt.contextItem === item))
				return Promise.resolve();
			return new Promise<void>((resolve): void => {
				const matchingWaiters = waiters.get(item) ?? new Set<() => void>();
				matchingWaiters.add(resolve);
				waiters.set(item, matchingWaiters);
			});
		},
	};
}

export function paintedSourceCorrelations(element: Element): string | null {
	return element.getAttribute('data-bridge-painted-source-correlations');
}

export function assertBridgeCodeViewHeaderGeometry(props: {
	readonly metadata: HTMLElement;
	readonly pierreHeaderTitle: HTMLElement;
}): void {
	const pierreHeader = props.pierreHeaderTitle.closest('[data-diffs-header]');
	if (!(pierreHeader instanceof HTMLElement)) {
		throw new Error('Expected the surrounding Pierre file header.');
	}
	expect(Math.round(pierreHeader.getBoundingClientRect().height)).toBe(40);
	const openFileButton = props.metadata.querySelector(
		'[data-testid="bridge-code-view-open-file-button"]',
	);
	if (!(openFileButton instanceof HTMLElement)) {
		throw new Error('Expected the shadcn open-file button inside the Pierre file header.');
	}
	const openFileButtonBox = openFileButton.getBoundingClientRect();
	expect(Math.round(openFileButtonBox.width)).toBe(28);
	expect(Math.round(openFileButtonBox.height)).toBe(28);
	const pierreHeaderBox = pierreHeader.getBoundingClientRect();
	expect(
		Math.abs(
			openFileButtonBox.y +
				openFileButtonBox.height / 2 -
				(pierreHeaderBox.y + pierreHeaderBox.height / 2),
		),
	).toBeLessThanOrEqual(1);
}

export function requireCurrentRenderedReviewRows(
	codeView: CodeView,
	item: CodeViewItem,
): CurrentRenderedReviewRows {
	const renderedItem = codeView
		.getRenderedItems()
		.find(
			(candidate): boolean =>
				candidate.id === item.id && candidate.item === item && candidate.element.isConnected,
		);
	if (renderedItem === undefined) {
		throw new Error('Expected exact current connected Pierre Review item.');
	}
	const shadowRoot = renderedItem.element.shadowRoot;
	if (shadowRoot === null) throw new Error('Expected real Pierre shadow root.');
	return {
		baseLines: [
			...shadowRoot.querySelectorAll<HTMLElement>('[data-deletions] [data-line][data-line-index]'),
		],
		clearHeadText: (): void => {
			for (const headLine of shadowRoot.querySelectorAll<HTMLElement>(
				'[data-additions] [data-line]',
			))
				headLine.textContent = '';
		},
		element: renderedItem.element,
		headLines: [
			...shadowRoot.querySelectorAll<HTMLElement>('[data-additions] [data-line][data-line-index]'),
		],
		shadowRoot,
	};
}

export function requireMountedCodeView(codeView: CodeView | null): CodeView {
	if (codeView === null) {
		throw new Error('Expected production BridgeCodeViewPanel to mount a public Pierre CodeView.');
	}
	return codeView;
}
