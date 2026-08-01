import { describe, expect, test } from 'vitest';

import {
	bridgeAppControlCommandSchema,
	bridgeAppControlProbeSchema,
} from './bridge-app-control.js';

describe('bridge app control schema', () => {
	test('accepts semantic IPC page-control commands as a discriminated union', () => {
		expect(
			bridgeAppControlCommandSchema.parse({
				method: 'bridge.diff.scrollToFile',
				itemId: 'item-source',
			}),
		).toEqual({
			method: 'bridge.diff.scrollToFile',
			itemId: 'item-source',
		});
		expect(
			bridgeAppControlCommandSchema.parse({
				method: 'bridge.diff.expandFile',
				itemId: 'item-source',
			}),
		).toEqual({
			method: 'bridge.diff.expandFile',
			itemId: 'item-source',
		});
		expect(
			bridgeAppControlCommandSchema.parse({
				method: 'bridge.diff.collapseFile',
				itemId: 'item-source',
			}),
		).toEqual({
			method: 'bridge.diff.collapseFile',
			itemId: 'item-source',
		});
		expect(
			bridgeAppControlCommandSchema.parse({
				method: 'bridge.fileTree.setFilter',
				filter: {
					surface: 'review',
					gitStatusFilter: 'modified',
					categoryFilter: 'source',
					showBinary: true,
					showLarge: false,
				},
			}),
		).toEqual({
			method: 'bridge.fileTree.setFilter',
			filter: {
				surface: 'review',
				gitStatusFilter: 'modified',
				categoryFilter: 'source',
				showBinary: true,
				showLarge: false,
			},
		});
		expect(
			bridgeAppControlCommandSchema.parse({
				method: 'bridge.fileTree.setFilter',
				filter: { surface: 'files', categoryFilter: 'docs' },
			}),
		).toEqual({
			method: 'bridge.fileTree.setFilter',
			filter: { surface: 'files', categoryFilter: 'docs' },
		});
		expect(
			bridgeAppControlCommandSchema.parse({
				method: 'bridge.fileTree.search',
				searchText: '^docs/.+\\.md$',
				searchMode: { kind: 'regex' },
			}),
		).toEqual({
			method: 'bridge.fileTree.search',
			searchText: '^docs/.+\\.md$',
			searchMode: { kind: 'regex' },
		});
	});

	test('rejects legacy and surface-invalid filter candidates atomically at the schema edge', () => {
		expect(() =>
			bridgeAppControlCommandSchema.parse({
				method: 'bridge.fileTree.setFilter',
				gitStatusFilter: 'modified',
				fileClassFilter: 'source',
			}),
		).toThrow();
		expect(() =>
			bridgeAppControlCommandSchema.parse({
				method: 'bridge.fileTree.setFilter',
				filter: { surface: 'files', categoryFilter: 'large' },
			}),
		).toThrow();
		expect(() =>
			bridgeAppControlCommandSchema.parse({
				method: 'bridge.fileTree.setFilter',
				filter: {
					surface: 'review',
					gitStatusFilter: 'all',
					categoryFilter: 'binary',
					showBinary: false,
					showLarge: false,
				},
			}),
		).toThrow();
	});

	test('rejects raw WebKit and command-palette shaped control payloads', () => {
		expect(() =>
			bridgeAppControlCommandSchema.parse({
				method: 'webview.evaluateJavaScript',
				script: 'document.body.innerHTML = ""',
			}),
		).toThrow();
		expect(() =>
			bridgeAppControlCommandSchema.parse({
				method: 'command.execute',
				commandId: 'commandPalette',
			}),
		).toThrow();
	});

	test('keeps the probe result typed for Swift IPC decoding', () => {
		expect(
			bridgeAppControlProbeSchema.parse({
				sequence: 1,
				method: 'bridge.fileTree.search',
				status: 'accepted',
				itemId: null,
				path: null,
				treeSearchText: 'runtime',
				treeSearchMode: { kind: 'text' },
				filterSurface: 'review',
				gitStatusFilter: 'all',
				categoryFilter: 'all',
				showBinary: false,
				showLarge: false,
				renderMode: { kind: 'codeView' },
				reason: null,
			}),
		).toMatchObject({
			method: 'bridge.fileTree.search',
			status: 'accepted',
			treeSearchText: 'runtime',
			treeSearchMode: { kind: 'text' },
		});
	});
});
