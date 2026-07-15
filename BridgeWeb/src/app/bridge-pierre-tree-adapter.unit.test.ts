import { describe, expect, test, vi } from 'vitest';

import {
	appendedOnlyPierreTreePaths,
	applyBridgePierreItemStream,
	expandAncestorDirectoriesForPierreTreePaths,
	mountedPierreFileRowElementsForModel,
	pierreFilePathFromEventTarget,
	pierreFilePathFromTreeEvent,
	pierreTreeScrollOwnerForModel,
	visiblePierreFileRowElementsForModel,
	type BridgePierreTreeContainerModel,
	type BridgePierreTreeDirectoryHandle,
	type BridgePierreTreeScrollOwner,
} from './bridge-pierre-tree-adapter.js';

describe('Bridge Pierre tree adapter', () => {
	test('detects append-only path growth', () => {
		const appendedPaths = appendedOnlyPierreTreePaths({
			previousPaths: ['Sources/App/View.swift'],
			nextPaths: ['Sources/App/View.swift', 'Sources/App/Model.swift'],
		});

		expect(appendedPaths).toEqual(['Sources/App/Model.swift']);
	});

	test('rejects reordered path changes as append-only updates', () => {
		const appendedPaths = appendedOnlyPierreTreePaths({
			previousPaths: ['Sources/App/View.swift'],
			nextPaths: ['Sources/App/Model.swift', 'Sources/App/View.swift'],
		});

		expect(appendedPaths).toBeNull();
	});

	test('uses append and patch updates for projection deltas and reserves setItems for source reset', () => {
		const model = new RecordingPierreItemStreamModel<string>(['item-a']);

		applyBridgePierreItemStream({
			getItem: (itemId: string) => model.getItem(itemId),
			items: ['item-a', 'item-b'],
			itemId: (item: string): string => item,
			patchItem: (item: string): void => {
				model.patchItem(item);
			},
			appendItems: (items: readonly string[]): void => {
				model.appendItems(items);
			},
			setItems: (items: readonly string[]): void => {
				model.setItems(items);
			},
			sourceReset: false,
		});

		expect(model.setItemsCalls).toEqual([]);
		expect(model.patchItems).toEqual(['item-a']);
		expect(model.appendItemBatches).toEqual([['item-b']]);

		applyBridgePierreItemStream({
			getItem: (itemId: string) => model.getItem(itemId),
			items: ['item-a'],
			itemId: (item: string): string => item,
			patchItem: (item: string): void => {
				model.patchItem(item);
			},
			appendItems: (items: readonly string[]): void => {
				model.appendItems(items);
			},
			setItems: (items: readonly string[]): void => {
				model.setItems(items);
			},
			sourceReset: true,
		});

		expect(model.setItemsCalls).toEqual([['item-a']]);
	});

	test('expands ancestor directories through mounted Pierre directory paths', () => {
		const sources = new RecordingDirectoryHandle();
		const app = new RecordingDirectoryHandle();
		const model = new RecordingPierreTreeModel(
			new Map([
				['mounted/Sources', sources],
				['mounted/Sources/App', app],
			]),
			new Map([
				['Sources', 'mounted/Sources'],
				['Sources/App', 'mounted/Sources/App'],
			]),
		);

		expandAncestorDirectoriesForPierreTreePaths({
			model,
			paths: ['Sources/App/Model.swift'],
		});

		expect(sources.expandCount).toBe(1);
		expect(app.expandCount).toBe(1);
	});

	test('can ignore stale expansion handles for review tree reveal retries', () => {
		const staleDirectory = new RecordingDirectoryHandle({
			expand: (): void => {
				throw new Error('stale directory handle');
			},
		});
		const model = new RecordingPierreTreeModel(new Map([['Sources', staleDirectory]]));

		expect((): void => {
			expandAncestorDirectoriesForPierreTreePaths({
				ignoreExpandErrors: true,
				model,
				paths: ['Sources/App/Model.swift'],
			});
		}).not.toThrow();
	});

	test('extracts Pierre file row paths from composed click events and closest targets', () => {
		const rowElement = new RecordingPierreFileRowElement('Sources/App/View.swift');
		const childTarget = {
			closest: vi.fn((): RecordingPierreFileRowElement => rowElement),
		};

		expect(
			pierreFilePathFromTreeEvent({
				composedPath: (): readonly unknown[] => [childTarget, rowElement],
			}),
		).toBe('Sources/App/View.swift');
		expect(pierreFilePathFromEventTarget(childTarget)).toBe('Sources/App/View.swift');
		expect(childTarget.closest).toHaveBeenCalledWith(
			'button[data-item-type="file"][data-item-path],[data-type="item"][data-item-type="file"][data-item-path]',
		);
	});

	test('returns only mounted Pierre file rows that intersect the scroll viewport', () => {
		const scrollOwner = new RecordingScrollOwner(boundingRect({ height: 240, top: 100 }));
		const mountedRows = [
			new RecordingPierreFileRowElement(
				'Sources/App/Above.swift',
				boundingRect({ height: 24, top: 60 }),
			),
			new RecordingPierreFileRowElement(
				'Sources/App/Visible.swift',
				boundingRect({ height: 24, top: 110 }),
			),
			new RecordingPierreFileRowElement(
				'Sources/App/Below.swift',
				boundingRect({ height: 24, top: 360 }),
			),
		];
		const shadowRoot = {
			querySelector: vi.fn((): BridgePierreTreeScrollOwner | null => scrollOwner),
			querySelectorAll: vi.fn((): Iterable<RecordingPierreFileRowElement> => mountedRows),
		};
		const rootContainer = {
			...shadowRoot,
			shadowRoot,
		};
		const model = {
			getFileTreeContainer: (): typeof rootContainer => rootContainer,
		} satisfies BridgePierreTreeContainerModel;

		expect(pierreTreeScrollOwnerForModel(model)).toBe(scrollOwner);
		expect(mountedPierreFileRowElementsForModel(model)).toEqual(mountedRows);
		expect(visiblePierreFileRowElementsForModel(model)).toEqual([mountedRows[1]]);
		expect(shadowRoot.querySelector).toHaveBeenCalledWith(
			'[data-file-tree-virtualized-scroll="true"]',
		);
		expect(shadowRoot.querySelectorAll).toHaveBeenCalledWith(
			'button[data-item-type="file"][data-item-path],[data-type="item"][data-item-type="file"][data-item-path]',
		);
	});

	test('uses the bounded mounted row window while the scroll viewport geometry is unavailable', () => {
		const mountedRows = [
			new RecordingPierreFileRowElement('Sources/App/First.swift'),
			new RecordingPierreFileRowElement('Sources/App/Second.swift'),
		];
		const model = fileTreeModelWithGeometry({
			mountedRows,
			scrollOwnerBounds: boundingRect({ height: 0, top: 0 }),
		});

		expect(visiblePierreFileRowElementsForModel(model)).toEqual(mountedRows);
	});

	test('uses the bounded mounted row window while every mounted row geometry is unavailable', () => {
		const mountedRows = [
			new RecordingPierreFileRowElement(
				'Sources/App/First.swift',
				boundingRect({ height: 0, top: 0 }),
			),
			new RecordingPierreFileRowElement(
				'Sources/App/Second.swift',
				boundingRect({ height: 0, top: 0 }),
			),
		];
		const model = fileTreeModelWithGeometry({
			mountedRows,
			scrollOwnerBounds: boundingRect({ height: 240, top: 100 }),
		});

		expect(visiblePierreFileRowElementsForModel(model)).toEqual(mountedRows);
	});
});

function fileTreeModelWithGeometry(props: {
	readonly mountedRows: readonly RecordingPierreFileRowElement[];
	readonly scrollOwnerBounds: DOMRect;
}): BridgePierreTreeContainerModel {
	const scrollOwner = new RecordingScrollOwner(props.scrollOwnerBounds);
	const shadowRoot = {
		querySelector: (): BridgePierreTreeScrollOwner => scrollOwner,
		querySelectorAll: (): Iterable<RecordingPierreFileRowElement> => props.mountedRows,
	};
	return {
		getFileTreeContainer: () => ({ ...shadowRoot, shadowRoot }),
	};
}

class RecordingDirectoryHandle implements BridgePierreTreeDirectoryHandle {
	expandCount = 0;
	readonly #expandOverride: (() => void) | undefined;

	constructor(props: { readonly expand?: () => void } = {}) {
		this.#expandOverride = props.expand;
	}

	isDirectory(): boolean {
		return true;
	}

	isExpanded(): boolean {
		return this.expandCount > 0;
	}

	expand(): void {
		this.#expandOverride?.();
		this.expandCount += 1;
	}
}

class RecordingScrollOwner implements BridgePierreTreeScrollOwner {
	scrollTop = 0;

	constructor(private readonly bounds: DOMRect = boundingRect({ height: 100, top: 0 })) {}

	addEventListener(): void {}

	dispatchEvent(): boolean {
		return true;
	}

	getBoundingClientRect(): DOMRect {
		return this.bounds;
	}

	querySelectorAll(): Iterable<RecordingPierreFileRowElement> {
		return [];
	}

	removeEventListener(): void {}
}

class RecordingPierreTreeModel {
	constructor(
		private readonly directoryByPath: ReadonlyMap<string, RecordingDirectoryHandle>,
		private readonly mountedPathByInputPath: ReadonlyMap<string, string> = new Map(),
	) {}

	getItem(path: string): RecordingDirectoryHandle | null {
		return this.directoryByPath.get(path) ?? null;
	}

	resolveMountedDirectoryPathFromInput(path: string): string | null {
		return this.mountedPathByInputPath.get(path) ?? null;
	}
}

class RecordingPierreFileRowElement {
	constructor(
		private readonly path: string | null,
		private readonly bounds: DOMRect = boundingRect({ height: 24, top: 0 }),
	) {}

	getBoundingClientRect(): DOMRect {
		return this.bounds;
	}

	getAttribute(name: string): string | null {
		if (name === 'data-item-type') {
			return 'file';
		}
		return name === 'data-item-path' ? this.path : null;
	}
}

function boundingRect(props: {
	readonly height: number;
	readonly top: number;
	readonly width?: number;
}): DOMRect {
	const width = props.width ?? 320;
	return {
		bottom: props.top + props.height,
		height: props.height,
		left: 0,
		right: width,
		top: props.top,
		width,
		x: 0,
		y: props.top,
		toJSON(): Record<string, number> {
			return {
				bottom: props.top + props.height,
				height: props.height,
				left: 0,
				right: width,
				top: props.top,
				width,
				x: 0,
				y: props.top,
			};
		},
	};
}

class RecordingPierreItemStreamModel<TItem> {
	readonly appendItemBatches: TItem[][] = [];
	readonly patchItems: TItem[] = [];
	readonly setItemsCalls: TItem[][] = [];
	readonly #itemsById = new Map<string, TItem>();

	constructor(items: readonly TItem[]) {
		for (const item of items) {
			this.#itemsById.set(String(item), item);
		}
	}

	appendItems(items: readonly TItem[]): void {
		this.appendItemBatches.push([...items]);
		for (const item of items) {
			this.#itemsById.set(String(item), item);
		}
	}

	getItem(itemId: string): TItem | undefined {
		return this.#itemsById.get(itemId);
	}

	patchItem(item: TItem): void {
		this.patchItems.push(item);
		this.#itemsById.set(String(item), item);
	}

	setItems(items: readonly TItem[]): void {
		this.setItemsCalls.push([...items]);
		this.#itemsById.clear();
		for (const item of items) {
			this.#itemsById.set(String(item), item);
		}
	}
}
