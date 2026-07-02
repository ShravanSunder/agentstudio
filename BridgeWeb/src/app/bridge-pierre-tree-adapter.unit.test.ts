import { describe, expect, test, vi } from 'vitest';

import {
	appendedOnlyPierreTreePaths,
	expandAncestorDirectoriesForPierreTreePaths,
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

	test('queries Pierre scroll owner and visible file row elements from the shadow row container', () => {
		const scrollOwner = new RecordingScrollOwner();
		const visibleRows = [
			new RecordingPierreFileRowElement('Sources/App/View.swift'),
			new RecordingPierreFileRowElement('Sources/App/Model.swift'),
		];
		const shadowRoot = {
			querySelector: vi.fn((): BridgePierreTreeScrollOwner | null => scrollOwner),
			querySelectorAll: vi.fn((): Iterable<RecordingPierreFileRowElement> => visibleRows),
		};
		const rootContainer = {
			...shadowRoot,
			shadowRoot,
		};
		const model = {
			getFileTreeContainer: (): typeof rootContainer => rootContainer,
		} satisfies BridgePierreTreeContainerModel;

		expect(pierreTreeScrollOwnerForModel(model)).toBe(scrollOwner);
		expect(visiblePierreFileRowElementsForModel(model)).toEqual(visibleRows);
		expect(shadowRoot.querySelector).toHaveBeenCalledWith(
			'[data-file-tree-virtualized-scroll="true"]',
		);
		expect(shadowRoot.querySelectorAll).toHaveBeenCalledWith(
			'[data-type="item"][data-item-type="file"][data-item-path]',
		);
	});
});

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
	addEventListener(): void {}

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
	constructor(private readonly path: string | null) {}

	getAttribute(name: string): string | null {
		if (name === 'data-item-type') {
			return 'file';
		}
		return name === 'data-item-path' ? this.path : null;
	}
}
