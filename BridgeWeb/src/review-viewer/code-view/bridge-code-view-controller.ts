import type {
	CodeViewItem,
	CodeViewLineSelection,
	CodeViewScrollBehavior,
	CodeViewScrollTarget,
} from '@pierre/diffs';

import type { BridgeCodeViewItem } from './bridge-code-view-materialization.js';

export interface BridgeCodeViewModel {
	readonly addItems: (items: readonly BridgeCodeViewItem[]) => void;
	readonly getItem: (id: string) => CodeViewItem | undefined;
	readonly updateItem: (item: BridgeCodeViewItem) => boolean;
	readonly updateItemId: (oldId: string, newId: string) => boolean;
	readonly scrollTo: (target: CodeViewScrollTarget) => void;
	readonly setSelectedLines: (selection: CodeViewLineSelection | null) => void;
	readonly renderImmediately?: () => void;
}

export interface BridgeCodeViewControllerProps {
	readonly model: BridgeCodeViewModel;
}

export interface ApplyBridgeCodeViewItemUpdateOptions {
	readonly scrollIntoView?: boolean;
	readonly scrollBehavior?: CodeViewScrollBehavior;
}

export type ApplyBridgeCodeViewItemUpdateResult = 'added' | 'updated' | 'unchanged';

export class BridgeCodeViewController {
	readonly #model: BridgeCodeViewModel;

	constructor(props: BridgeCodeViewControllerProps) {
		this.#model = props.model;
	}

	applyItemUpdate(
		item: BridgeCodeViewItem,
		options: ApplyBridgeCodeViewItemUpdateOptions = {},
	): ApplyBridgeCodeViewItemUpdateResult {
		const existingItem = this.#model.getItem(item.id);
		let result: ApplyBridgeCodeViewItemUpdateResult;
		if (existingItem === undefined) {
			this.#model.addItems([item]);
			result = 'added';
		} else {
			result = this.#model.updateItem(item) ? 'updated' : 'unchanged';
		}

		if (options.scrollIntoView === true) {
			this.scrollToItem(item.id, options.scrollBehavior ?? 'instant');
		}
		this.#model.renderImmediately?.();
		return result;
	}

	scrollToItem(itemId: string, behavior: CodeViewScrollBehavior = 'instant'): void {
		if (this.#model.getItem(itemId) === undefined) {
			return;
		}
		this.#model.scrollTo({
			type: 'item',
			id: itemId,
			align: 'start',
			behavior,
		});
	}

	setSelectedLines(selection: CodeViewLineSelection | null): void {
		this.#model.setSelectedLines(selection);
	}

	updateItemId(oldId: string, newId: string): boolean {
		return this.#model.updateItemId(oldId, newId);
	}
}
