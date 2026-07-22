import type { CodeView, CodeViewItem } from '@pierre/diffs';

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
