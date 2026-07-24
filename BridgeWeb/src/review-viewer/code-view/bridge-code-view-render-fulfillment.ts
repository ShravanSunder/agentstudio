import type { CodeViewItem, PostRenderPhase } from '@pierre/diffs';
import type { CodeViewHandle } from '@pierre/diffs/react';

import type {
	BridgeMainRenderedItemReadback,
	BridgeMainRenderFulfillmentCoordinator,
	BridgeMainRenderReadback,
} from '../../core/comm-worker/bridge-main-render-fulfillment-coordinator.js';
import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';

export type BridgeCodeViewRenderObservationCoordinator = Pick<
	BridgeMainRenderFulfillmentCoordinator,
	'observePostRender' | 'reconcilePublication'
>;

export type BridgeCodeViewRenderFulfillmentCoordinator =
	BridgeCodeViewRenderObservationCoordinator &
		Pick<BridgeMainRenderFulfillmentCoordinator, 'bindPublicationItem' | 'isBoundFinalItem'>;

export interface ObserveBridgeCodeViewRenderFulfillmentProps {
	readonly contextItem: CodeViewItem;
	readonly getCodeViewHandle: () => CodeViewHandle<undefined> | null;
	readonly itemId: string;
	readonly phase: PostRenderPhase;
	readonly renderedElement?: HTMLElement;
	readonly renderFulfillmentCoordinator: BridgeCodeViewRenderObservationCoordinator;
	readonly selectedCodeViewItem: BridgeMainCodeViewItem | null | undefined;
	readonly visibleCodeViewItems: readonly BridgeMainCodeViewItem[] | undefined;
}

export function observeBridgeCodeViewRenderFulfillment(
	props: ObserveBridgeCodeViewRenderFulfillmentProps,
): void {
	const exactWorkerItem = exactWorkerItemForPostRender(props);
	if (exactWorkerItem === undefined) return;
	const postRenderReadback =
		props.renderedElement === undefined
			? renderReadbackForExactWorkerItem({
					exactWorkerItem,
					getCodeViewHandle: props.getCodeViewHandle,
					itemId: props.itemId,
				})
			: postRenderReadbackForExactWorkerItem({
					exactWorkerItem,
					getCodeViewHandle: props.getCodeViewHandle,
					itemId: props.itemId,
					renderedElement: props.renderedElement,
				});
	props.renderFulfillmentCoordinator.observePostRender({
		...postRenderReadback,
		contextItem: exactWorkerItem,
		itemId: props.itemId,
		phase: props.phase,
	});
	if (props.phase === 'unmount') return;
	globalThis.queueMicrotask((): void => {
		props.renderFulfillmentCoordinator.reconcilePublication({
			...renderReadbackForExactWorkerItem({
				exactWorkerItem,
				getCodeViewHandle: props.getCodeViewHandle,
				itemId: props.itemId,
			}),
			itemId: props.itemId,
		});
	});
}

export function reconcileBridgeCodeViewRenderFulfillment(props: {
	readonly exactPresentationItem: BridgeMainCodeViewItem;
	readonly getCodeViewHandle: () => CodeViewHandle<undefined> | null;
	readonly renderFulfillmentCoordinator: BridgeCodeViewRenderObservationCoordinator;
}): void {
	props.renderFulfillmentCoordinator.reconcilePublication({
		...renderReadbackForExactWorkerItem({
			exactWorkerItem: props.exactPresentationItem,
			getCodeViewHandle: props.getCodeViewHandle,
			itemId: props.exactPresentationItem.id,
		}),
		itemId: props.exactPresentationItem.id,
	});
}

function exactWorkerItemForPostRender(
	props: ObserveBridgeCodeViewRenderFulfillmentProps,
): BridgeMainCodeViewItem | undefined {
	if (
		props.selectedCodeViewItem === props.contextItem &&
		props.selectedCodeViewItem.id === props.itemId
	) {
		return props.selectedCodeViewItem;
	}
	return props.visibleCodeViewItems?.find(
		(item): boolean => item === props.contextItem && item.id === props.itemId,
	);
}

function postRenderReadbackForExactWorkerItem(props: {
	readonly exactWorkerItem: BridgeMainCodeViewItem;
	readonly getCodeViewHandle: () => CodeViewHandle<undefined> | null;
	readonly itemId: string;
	readonly renderedElement: HTMLElement;
}): BridgeMainRenderReadback {
	return {
		readCurrentItem: (): BridgeMainCodeViewItem | undefined => {
			const codeViewHandle = props.getCodeViewHandle();
			if (codeViewHandle === null || codeViewHandle.getInstance() === undefined) {
				return props.exactWorkerItem;
			}
			const currentItem = codeViewHandle.getItem(props.itemId);
			return currentItem === props.exactWorkerItem ? props.exactWorkerItem : undefined;
		},
		readRenderedItem: (): BridgeMainRenderedItemReadback => ({
			element: props.renderedElement,
			item: props.exactWorkerItem,
			readableContentMatchesItem: bridgeCodeViewRenderedItemHasReadableContent({
				element: props.renderedElement,
				item: props.exactWorkerItem,
			}),
		}),
	};
}

function renderReadbackForExactWorkerItem(props: {
	readonly exactWorkerItem: BridgeMainCodeViewItem;
	readonly getCodeViewHandle: () => CodeViewHandle<undefined> | null;
	readonly itemId: string;
}): BridgeMainRenderReadback {
	return {
		readCurrentItem: (): BridgeMainCodeViewItem | undefined => {
			const currentItem = props.getCodeViewHandle()?.getItem(props.itemId);
			return currentItem === props.exactWorkerItem ? props.exactWorkerItem : undefined;
		},
		readRenderedItem: (): BridgeMainRenderedItemReadback | null => {
			const renderedItem = props
				.getCodeViewHandle()
				?.getInstance()
				?.getRenderedItems()
				.find((candidate): boolean => candidate.id === props.itemId);
			if (renderedItem?.item !== props.exactWorkerItem) return null;
			return {
				element: renderedItem.element,
				item: props.exactWorkerItem,
				readableContentMatchesItem: bridgeCodeViewRenderedItemHasReadableContent({
					element: renderedItem.element,
					item: props.exactWorkerItem,
				}),
			};
		},
	};
}

function bridgeCodeViewRenderedItemHasReadableContent(props: {
	readonly element: HTMLElement;
	readonly item: BridgeMainCodeViewItem;
}): boolean {
	const item = props.item;
	if (item.type === 'file') {
		const renderedLineElements = queryOpenShadowRoots(
			props.element,
			'[data-line][data-line-index]',
		);
		if (item.file.contents.length === 0 && item.bridgeMetadata.lineCount !== 0) return false;
		return bridgeCodeViewRenderedSourceHasReadableContent({
			renderedLineElements,
			sourceLineAtNumber: (lineNumber): string | null =>
				bridgeCodeViewFileSourceLineAtIndex(item.file.contents, lineNumber - 1),
			...(item.file.contents.length === 0 ? { sourceLineCount: 0 } : {}),
		});
	}
	const fileDiff = item.fileDiff;
	if (
		fileDiff.deletionLines.length === 0 &&
		fileDiff.additionLines.length === 0 &&
		item.bridgeMetadata.lineCount !== 0
	)
		return false;
	return (
		bridgeCodeViewRenderedSourceHasReadableContent({
			renderedLineElements: queryOpenShadowRoots(
				props.element,
				'[data-deletions] [data-line][data-line-index]',
			),
			sourceLineAtNumber: (lineNumber): string | null =>
				bridgeCodeViewDiffSourceLineAtNumber({
					fileDiff,
					lineNumber,
					side: 'deletions',
				}),
			sourceLineCount: fileDiff.deletionLines.length,
		}) &&
		bridgeCodeViewRenderedSourceHasReadableContent({
			renderedLineElements: queryOpenShadowRoots(
				props.element,
				'[data-additions] [data-line][data-line-index]',
			),
			sourceLineAtNumber: (lineNumber): string | null =>
				bridgeCodeViewDiffSourceLineAtNumber({
					fileDiff,
					lineNumber,
					side: 'additions',
				}),
			sourceLineCount: fileDiff.additionLines.length,
		})
	);
}

function bridgeCodeViewRenderedSourceHasReadableContent(props: {
	readonly renderedLineElements: readonly Element[];
	readonly sourceLineAtNumber: (lineNumber: number) => string | null;
	readonly sourceLineCount?: number;
}): boolean {
	if (props.sourceLineCount === 0) return props.renderedLineElements.length === 0;
	if (props.renderedLineElements.length === 0) return false;
	return props.renderedLineElements.every((lineElement): boolean => {
		const lineNumber = Number.parseInt(lineElement.getAttribute('data-line') ?? '', 10);
		if (!Number.isInteger(lineNumber) || lineNumber <= 0) return false;
		const expectedSourceLine = props.sourceLineAtNumber(lineNumber);
		if (expectedSourceLine === null) return false;
		return (
			bridgeCodeViewNormalizeRenderedLine(lineElement.textContent ?? '') ===
			bridgeCodeViewNormalizeRenderedLine(expectedSourceLine)
		);
	});
}

function bridgeCodeViewNormalizeRenderedLine(line: string): string {
	return line.replace(/(?:\r\n|\r|\n)$/, '');
}

function bridgeCodeViewDiffSourceLineAtNumber(props: {
	readonly fileDiff: Extract<BridgeMainCodeViewItem, { readonly type: 'diff' }>['fileDiff'];
	readonly lineNumber: number;
	readonly side: 'additions' | 'deletions';
}): string | null {
	if (!Number.isInteger(props.lineNumber) || props.lineNumber <= 0) return null;
	const isAddition = props.side === 'additions';
	for (const hunk of props.fileDiff.hunks) {
		const lineStart = isAddition ? hunk.additionStart : hunk.deletionStart;
		const lineCount = isAddition ? hunk.additionCount : hunk.deletionCount;
		if (props.lineNumber < lineStart || props.lineNumber >= lineStart + lineCount) continue;
		const firstSourceLineIndex = isAddition ? hunk.additionLineIndex : hunk.deletionLineIndex;
		const sourceLines = isAddition ? props.fileDiff.additionLines : props.fileDiff.deletionLines;
		return sourceLines[firstSourceLineIndex + props.lineNumber - lineStart] ?? null;
	}
	return null;
}

function bridgeCodeViewFileSourceLineAtIndex(
	contents: string,
	targetLineIndex: number,
): string | null {
	if (!Number.isInteger(targetLineIndex) || targetLineIndex < 0) return null;
	let currentLineIndex = 0;
	let currentLineStart = 0;
	for (let characterIndex = 0; characterIndex < contents.length; characterIndex += 1) {
		const character = contents[characterIndex];
		if (character !== '\n' && character !== '\r') continue;
		if (currentLineIndex === targetLineIndex) {
			return contents.slice(currentLineStart, characterIndex);
		}
		if (character === '\r' && contents[characterIndex + 1] === '\n') {
			characterIndex += 1;
		}
		currentLineIndex += 1;
		currentLineStart = characterIndex + 1;
	}
	return currentLineIndex === targetLineIndex ? contents.slice(currentLineStart) : null;
}

function queryOpenShadowRoots(root: Element | ShadowRoot, selector: string): readonly Element[] {
	const matches = [...root.querySelectorAll(selector)];
	if (root instanceof Element && root.shadowRoot !== null) {
		matches.push(...queryOpenShadowRoots(root.shadowRoot, selector));
	}
	for (const descendant of root.querySelectorAll('*')) {
		if (descendant.shadowRoot !== null) {
			matches.push(...queryOpenShadowRoots(descendant.shadowRoot, selector));
		}
	}
	return matches;
}
