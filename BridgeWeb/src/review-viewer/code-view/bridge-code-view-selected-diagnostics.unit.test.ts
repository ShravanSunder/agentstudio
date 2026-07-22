import { parseDiffFromFile } from '@pierre/diffs';
import { describe, expect, test } from 'vitest';

import type { BridgeMainCodeViewItem } from '../../core/comm-worker/bridge-main-render-snapshot-store.js';
import {
	emptyMaterializationDiagnostic,
	type BridgeCodeViewMaterializationDiagnostic,
} from './bridge-code-view-panel-support.js';
import {
	selectedContentDiagnosticsForPanel,
	selectedMaterializationDiagnosticForPanel,
} from './bridge-code-view-selected-diagnostics.js';

describe('Bridge CodeView selected diagnostics', () => {
	test('derives selected content facts from a worker-prepared diff item', () => {
		const selectedCodeViewItem = makeSelectedCodeViewItem();

		const diagnostics = selectedContentDiagnosticsForPanel({
			selectedCodeViewItem,
			selectedItemId: selectedCodeViewItem.id,
		});

		expect(diagnostics).toMatchObject({
			cacheKeys: 'base:pierre-content:sha256:base,head:pierre-content:sha256:head',
			roleCount: 2,
			roleNames: 'base,head',
			state: 'ready',
			summary: {
				cacheKeyCount: 2,
				lineCount: 2,
			},
		});
		expect(diagnostics.summary.characterCount).toBeGreaterThan(0);
	});

	test('reports actual selected diff lines when presentation metadata has no line extent', () => {
		// Arrange
		const selectedCodeViewItem = makeSelectedCodeViewItem();
		selectedCodeViewItem.bridgeMetadata.lineCount = 0;

		// Act
		const diagnostics = selectedContentDiagnosticsForPanel({
			selectedCodeViewItem,
			selectedItemId: selectedCodeViewItem.id,
		});

		// Assert
		expect(diagnostics.summary.lineCount).toBe(2);
	});

	test('maps added-file diff cache keys by semantic role', () => {
		const selectedCodeViewItem = makeOneSidedSelectedCodeViewItem({
			cacheKey: 'pierre-content:empty|pierre-content:sha256:head',
			contentRoles: ['head'],
		});

		const diagnostics = selectedContentDiagnosticsForPanel({
			selectedCodeViewItem,
			selectedItemId: selectedCodeViewItem.id,
		});

		expect(diagnostics.cacheKeys).toBe('head:pierre-content:sha256:head');
		expect(diagnostics.summary.cacheKeyCount).toBe(1);
	});

	test('maps deleted-file diff cache keys by semantic role', () => {
		const selectedCodeViewItem = makeOneSidedSelectedCodeViewItem({
			cacheKey: 'pierre-content:sha256:base|pierre-content:empty',
			contentRoles: ['base'],
		});

		const diagnostics = selectedContentDiagnosticsForPanel({
			selectedCodeViewItem,
			selectedItemId: selectedCodeViewItem.id,
		});

		expect(diagnostics.cacheKeys).toBe('base:pierre-content:sha256:base');
		expect(diagnostics.summary.cacheKeyCount).toBe(1);
	});

	test('synthesizes selected materialization facts from a worker-prepared diff item', () => {
		const selectedCodeViewItem = makeSelectedCodeViewItem();

		const diagnostic = selectedMaterializationDiagnosticForPanel({
			materializationDiagnostic: emptyMaterializationDiagnostic(),
			selectedCodeViewItem,
		});

		expect(diagnostic).toMatchObject({
			updateResult: 'updated',
			itemType: 'diff',
			itemVersion: 7,
			modelContentState: 'hydrated',
			modelItemVersion: 7,
			additionLineCount: 1,
			deletionLineCount: 1,
			fileLineCount: 0,
		});
	});

	test('keeps explicit materialization facts when the panel materializer has run', () => {
		const selectedCodeViewItem = makeSelectedCodeViewItem();
		const materializationDiagnostic = {
			...emptyMaterializationDiagnostic(),
			updateResult: 'unchanged',
			itemType: 'diff',
			itemVersion: 6,
		} satisfies BridgeCodeViewMaterializationDiagnostic;

		const diagnostic = selectedMaterializationDiagnosticForPanel({
			materializationDiagnostic,
			selectedCodeViewItem,
		});

		expect(diagnostic).toBe(materializationDiagnostic);
	});
});

function makeSelectedCodeViewItem(): BridgeMainCodeViewItem {
	const fileDiff = parseDiffFromFile(
		{
			name: 'Sources/App/View.swift',
			contents: 'let before = 1\n',
			cacheKey: 'pierre-content:sha256:base',
		},
		{
			name: 'Sources/App/View.swift',
			contents: 'let after = 2\n',
			cacheKey: 'pierre-content:sha256:head',
		},
	);
	fileDiff.cacheKey = 'pierre-content:sha256:base|pierre-content:sha256:head';
	return {
		id: 'item-source',
		type: 'diff',
		fileDiff,
		version: 7,
		bridgeMetadata: {
			itemId: 'item-source',
			displayPath: 'Sources/App/View.swift',
			contentState: 'hydrated',
			contentRoles: ['base', 'head'],
			cacheKey: 'pierre-content:sha256:base|pierre-content:sha256:head',
			lineCount: 2,
		},
	};
}

function makeOneSidedSelectedCodeViewItem(props: {
	readonly cacheKey: string;
	readonly contentRoles: readonly ['base'] | readonly ['head'];
}): BridgeMainCodeViewItem {
	const fileDiff = parseDiffFromFile(
		{
			name: 'Sources/App/View.swift',
			contents: props.contentRoles[0] === 'base' ? 'let before = 1\n' : '',
			cacheKey: 'pierre-content:sha256:base',
		},
		{
			name: 'Sources/App/View.swift',
			contents: props.contentRoles[0] === 'head' ? 'let after = 2\n' : '',
			cacheKey: 'pierre-content:sha256:head',
		},
	);
	fileDiff.cacheKey = props.cacheKey;
	return {
		id: 'item-one-sided',
		type: 'diff',
		fileDiff,
		version: 7,
		bridgeMetadata: {
			itemId: 'item-one-sided',
			displayPath: 'Sources/App/View.swift',
			contentState: 'hydrated',
			contentRoles: props.contentRoles,
			cacheKey: props.cacheKey,
			lineCount: 1,
		},
	};
}
