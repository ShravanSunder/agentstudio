import { describe, expect, test } from 'vitest';

import {
	appendedOnlyPierreTreePaths,
	expandAncestorDirectoriesForPierreTreePaths,
	type BridgePierreTreeDirectoryHandle,
} from '../app/bridge-pierre-tree-adapter.js';
import { makeFileDescriptor } from './bridge-file-viewer-browser-test-fixtures.js';
import { createBridgeFileViewerTreeSelectionCoordinator } from './bridge-file-viewer-pierre-tree-runtime.js';
import { descriptorRefsForPierreVisibleFileRows } from './bridge-file-viewer-pierre-visible-demand.js';

describe('BridgeFileViewerTreePanel append behavior', () => {
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

	test('expands ancestor directories for appended paths', () => {
		const sources = new RecordingDirectoryHandle();
		const app = new RecordingDirectoryHandle();
		const model = new RecordingFileTreeModel(
			new Map([
				['Sources', sources],
				['Sources/App', app],
			]),
		);

		expandAncestorDirectoriesForPierreTreePaths({
			model,
			paths: ['Sources/App/Model.swift'],
		});

		expect(sources.expandCount).toBe(1);
		expect(app.expandCount).toBe(1);
	});

	test('expands ancestors for appended paths beyond the old startup chunk reveal cap', () => {
		const directoryByPath = new Map<string, RecordingDirectoryHandle>();
		const appendedPaths = Array.from({ length: 20 }, (_, index): string => {
			const path = `Sources/Module${index}/File.swift`;
			directoryByPath.set('Sources', new RecordingDirectoryHandle());
			directoryByPath.set(`Sources/Module${index}`, new RecordingDirectoryHandle());
			return path;
		});
		const model = new RecordingFileTreeModel(directoryByPath);

		expandAncestorDirectoriesForPierreTreePaths({
			model,
			paths: appendedPaths,
		});

		expect(directoryByPath.get('Sources/Module19')?.expandCount).toBe(1);
	});
});

describe('BridgeFileViewer Pierre tree runtime selection coordination', () => {
	test('dedupes the click event paired with a Pierre selection change', () => {
		const openedPaths: string[] = [];
		const selectionCoordinator = createBridgeFileViewerTreeSelectionCoordinator({
			openOrRequestPath: (path: string): void => {
				openedPaths.push(path);
			},
		});

		selectionCoordinator.recordPierreSelectionPath('src/ready.ts');
		selectionCoordinator.handleClickedPath('src/ready.ts');

		expect(openedPaths).toEqual(['src/ready.ts']);
	});

	test('allows a later metadata-only retry click after deduping the paired click', () => {
		const requestedPaths: string[] = [];
		const selectionCoordinator = createBridgeFileViewerTreeSelectionCoordinator({
			openOrRequestPath: (path: string): void => {
				requestedPaths.push(path);
			},
		});

		selectionCoordinator.recordPierreSelectionPath('src/metadata-only.ts');
		selectionCoordinator.handleClickedPath('src/metadata-only.ts');
		selectionCoordinator.handleClickedPath('src/metadata-only.ts');

		expect(requestedPaths).toEqual(['src/metadata-only.ts', 'src/metadata-only.ts']);
	});
});

describe('BridgeFileViewerTreePanel Pierre visible demand adapter', () => {
	test('extracts fetchable descriptor refs from visible Pierre file rows', () => {
		const descriptor = makeFileDescriptor({
			contentHandle: 'visible-content',
			fileId: 'file-visible',
			path: 'src/visible.ts',
		});

		const descriptorRefs = descriptorRefsForPierreVisibleFileRows({
			fileDescriptorByPath: new Map([[descriptor.path, descriptor]]),
			rowElements: [new RecordingPierreFileRowElement(descriptor.path)],
		});

		expect(descriptorRefs).toEqual([descriptor.contentDescriptor.ref]);
	});

	test('skips non-fetchable and duplicate Pierre visible file rows', () => {
		const textDescriptor = makeFileDescriptor({
			contentHandle: 'text-content',
			fileId: 'file-text',
			path: 'src/text.ts',
		});
		const binaryDescriptor = makeFileDescriptor({
			contentHandle: 'binary-content',
			fileId: 'file-binary',
			isBinary: true,
			path: 'assets/icon.png',
		});
		const unavailableDescriptor = makeFileDescriptor({
			contentHandle: 'unavailable-content',
			fileId: 'file-unavailable',
			path: 'generated/large.log',
			virtualizedExtentKind: 'unavailable',
		});

		const descriptorRefs = descriptorRefsForPierreVisibleFileRows({
			fileDescriptorByPath: new Map([
				[textDescriptor.path, textDescriptor],
				[binaryDescriptor.path, binaryDescriptor],
				[unavailableDescriptor.path, unavailableDescriptor],
			]),
			rowElements: [
				new RecordingPierreFileRowElement(textDescriptor.path),
				new RecordingPierreFileRowElement(binaryDescriptor.path),
				new RecordingPierreFileRowElement(unavailableDescriptor.path),
				new RecordingPierreFileRowElement(textDescriptor.path),
				new RecordingPierreFileRowElement(null),
			],
		});

		expect(descriptorRefs).toEqual([textDescriptor.contentDescriptor.ref]);
	});
});

class RecordingDirectoryHandle implements BridgePierreTreeDirectoryHandle {
	expandCount = 0;

	isDirectory(): boolean {
		return true;
	}

	isExpanded(): boolean {
		return this.expandCount > 0;
	}

	expand(): void {
		this.expandCount += 1;
	}
}

class RecordingFileTreeModel {
	constructor(private readonly directoryByPath: ReadonlyMap<string, RecordingDirectoryHandle>) {}

	getItem(path: string): RecordingDirectoryHandle | null {
		return this.directoryByPath.get(path) ?? null;
	}
}

class RecordingPierreFileRowElement {
	constructor(private readonly path: string | null) {}

	getAttribute(name: string): string | null {
		return name === 'data-item-path' ? this.path : null;
	}
}
