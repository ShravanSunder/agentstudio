import { describe, expect, test } from 'vitest';

import { createBridgeFileViewerSelectionGate } from './bridge-file-viewer-selection-gate.js';

interface DeferredPreparation {
	readonly prepare: () => Promise<boolean>;
	readonly settle: (prepared: boolean) => void;
	readonly callCount: () => number;
}

function deferredPreparation(): DeferredPreparation {
	let resolvePreparation: ((prepared: boolean) => void) | null = null;
	let calls = 0;
	return {
		callCount: (): number => calls,
		prepare: (): Promise<boolean> => {
			calls += 1;
			return new Promise<boolean>((resolve): void => {
				resolvePreparation = resolve;
			});
		},
		settle: (prepared): void => {
			if (resolvePreparation === null) throw new Error('Expected a pending preparation.');
			resolvePreparation(prepared);
		},
	};
}

describe('createBridgeFileViewerSelectionGate', () => {
	test('applies a first selection without preparing editors', async () => {
		// Arrange
		const gate = createBridgeFileViewerSelectionGate();
		const preparation = deferredPreparation();
		const committed: string[] = [];

		// Act
		const outcome = await gate.request({
			commit: (): boolean => {
				committed.push('file-a');
				return true;
			},
			currentFileId: null,
			nextFileId: 'file-a',
			prepareActiveEditors: preparation.prepare,
		});

		// Assert
		expect(outcome).toBe('committed');
		expect(committed).toEqual(['file-a']);
		expect(preparation.callCount()).toBe(0);
	});

	test('waits for editors to be flushed before leaving the displayed file', async () => {
		// Arrange
		const gate = createBridgeFileViewerSelectionGate();
		const preparation = deferredPreparation();
		const committed: string[] = [];

		// Act
		const pendingOutcome = gate.request({
			commit: (): boolean => {
				committed.push('file-b');
				return true;
			},
			currentFileId: 'file-a',
			nextFileId: 'file-b',
			prepareActiveEditors: preparation.prepare,
		});
		const committedBeforeFlush = [...committed];
		preparation.settle(true);
		const outcome = await pendingOutcome;

		// Assert
		expect(committedBeforeFlush).toEqual([]);
		expect(outcome).toBe('committed');
		expect(committed).toEqual(['file-b']);
	});

	test('keeps the displayed file when an editor cannot be flushed', async () => {
		// Arrange
		const gate = createBridgeFileViewerSelectionGate();
		const committed: string[] = [];

		// Act
		const outcome = await gate.request({
			commit: (): boolean => {
				committed.push('file-b');
				return true;
			},
			currentFileId: 'file-a',
			nextFileId: 'file-b',
			prepareActiveEditors: async (): Promise<boolean> => {
				throw new Error('draft.flush was not acknowledged');
			},
		});

		// Assert
		expect(outcome).toBe('refused');
		expect(committed).toEqual([]);
	});

	test('treats clearing the selection as leaving the displayed file', async () => {
		// Arrange
		const gate = createBridgeFileViewerSelectionGate();
		const committed: string[] = [];

		// Act
		const outcome = await gate.request({
			commit: (): boolean => {
				committed.push('cleared');
				return true;
			},
			currentFileId: 'file-a',
			nextFileId: null,
			prepareActiveEditors: async (): Promise<boolean> => false,
		});

		// Assert
		expect(outcome).toBe('refused');
		expect(committed).toEqual([]);
	});

	test('drops an older request whose preparation finishes after a newer one', async () => {
		// Arrange
		const gate = createBridgeFileViewerSelectionGate();
		const olderPreparation = deferredPreparation();
		const newerPreparation = deferredPreparation();
		const committed: string[] = [];
		const commitFile =
			(fileId: string): (() => boolean) =>
			(): boolean => {
				committed.push(fileId);
				return true;
			};

		// Act
		const olderOutcome = gate.request({
			commit: commitFile('file-b'),
			currentFileId: 'file-a',
			nextFileId: 'file-b',
			prepareActiveEditors: olderPreparation.prepare,
		});
		const newerOutcome = gate.request({
			commit: commitFile('file-c'),
			currentFileId: 'file-a',
			nextFileId: 'file-c',
			prepareActiveEditors: newerPreparation.prepare,
		});
		newerPreparation.settle(true);
		olderPreparation.settle(true);

		// Assert
		expect(await newerOutcome).toBe('committed');
		expect(await olderOutcome).toBe('superseded');
		expect(committed).toEqual(['file-c']);
	});

	test('reports an inactive viewer instead of a committed change', async () => {
		// Arrange
		const gate = createBridgeFileViewerSelectionGate();

		// Act
		const outcome = await gate.request({
			commit: (): boolean => false,
			currentFileId: 'file-a',
			nextFileId: 'file-b',
			prepareActiveEditors: async (): Promise<boolean> => true,
		});

		// Assert
		expect(outcome).toBe('inactive');
	});
});
