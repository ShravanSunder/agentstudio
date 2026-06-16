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

export class BridgeCodeViewController {
	readonly #model: BridgeCodeViewModel;

	constructor(props: BridgeCodeViewControllerProps) {
		this.#model = props.model;
	}

	applyItemUpdate(
		item: BridgeCodeViewItem,
		options: ApplyBridgeCodeViewItemUpdateOptions = {},
	): void {
		const existingItem = this.#model.getItem(item.id);
		if (existingItem === undefined) {
			this.#model.addItems([item]);
		} else {
			this.#model.updateItem(item);
		}

		if (options.scrollIntoView === true) {
			this.scrollToItem(item.id, options.scrollBehavior ?? 'instant');
		}
		this.#model.renderImmediately?.();
	}

	scrollToItem(itemId: string, behavior: CodeViewScrollBehavior = 'instant'): void {
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
