import { describe, expect, test } from 'vitest';

import { makeFileDescriptor } from './bridge-file-viewer-browser-test-fixtures.js';
import { descriptorRefsForPierreVisibleFileRows } from './bridge-file-viewer-pierre-visible-demand.js';
import {
	appendedOnlyPaths,
	expandAncestorDirectoriesForAppendedPaths,
	type BridgeFileViewerTreeDirectoryHandle,
} from './bridge-file-viewer-tree-panel.js';

describe('BridgeFileViewerTreePanel append behavior', () => {
	test('detects append-only path growth', () => {
		const appendedPaths = appendedOnlyPaths({
			previousPaths: ['Sources/App/View.swift'],
			nextPaths: ['Sources/App/View.swift', 'Sources/App/Model.swift'],
		});

		expect(appendedPaths).toEqual(['Sources/App/Model.swift']);
	});

	test('rejects reordered path changes as append-only updates', () => {
		const appendedPaths = appendedOnlyPaths({
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

		expandAncestorDirectoriesForAppendedPaths({
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

		expandAncestorDirectoriesForAppendedPaths({
			model,
			paths: appendedPaths,
		});

		expect(directoryByPath.get('Sources/Module19')?.expandCount).toBe(1);
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

class RecordingDirectoryHandle implements BridgeFileViewerTreeDirectoryHandle {
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
