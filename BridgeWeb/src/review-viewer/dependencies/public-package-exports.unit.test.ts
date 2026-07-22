import {
	CodeView,
	File,
	FileDiff,
	WorkerPoolContextProvider,
	type CodeViewHandle,
} from '@pierre/diffs/react';
import { WorkerPoolManager } from '@pierre/diffs/worker';
import { prepareFileTreeInput, preparePresortedFileTreeInput } from '@pierre/trees';
import {
	FileTree,
	useFileTree,
	useFileTreeSearch,
	useFileTreeSelection,
} from '@pierre/trees/react';
import { describe, expect, expectTypeOf, test } from 'vitest';
import { useStore } from 'zustand';
import { createStore } from 'zustand/vanilla';

describe('public package exports', () => {
	test('uses only installed public Pierre and Zustand entrypoints', () => {
		expect(typeof CodeView).toBe('object');
		expect(typeof File).toBe('function');
		expect(typeof FileDiff).toBe('function');
		expect(typeof WorkerPoolContextProvider).toBe('function');
		expect(typeof WorkerPoolManager).toBe('function');
		expect(typeof prepareFileTreeInput).toBe('function');
		expect(typeof preparePresortedFileTreeInput).toBe('function');
		expect(typeof FileTree).toBe('function');
		expect(typeof useFileTree).toBe('function');
		expect(typeof useFileTreeSearch).toBe('function');
		expect(typeof useFileTreeSelection).toBe('function');
		expect(typeof useStore).toBe('function');
		expect(typeof createStore).toBe('function');
	});

	test('keeps imperative CodeView handle available as an exported type', () => {
		expectTypeOf<CodeViewHandle<undefined>>().toHaveProperty('addItems');
		expectTypeOf<CodeViewHandle<undefined>>().toHaveProperty('updateItem');
		expectTypeOf<CodeViewHandle<undefined>>().toHaveProperty('updateItemId');
		expectTypeOf<CodeViewHandle<undefined>>().toHaveProperty('scrollTo');
		expectTypeOf<CodeViewHandle<undefined>>().toHaveProperty('setSelectedLines');
	});
});
