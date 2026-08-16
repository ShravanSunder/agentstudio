import { describe, expect, test } from 'vitest';

import { isMarkdownPath, resolveBridgeFileMarkdownIntent } from './bridge-file-markdown-intent.js';

describe('File Markdown render intent', () => {
	test('uses complete selected Markdown file contents and current File identity', () => {
		const decision = resolveBridgeFileMarkdownIntent({
			displaySource: { sourceId: 'worktree-1', generation: 7 },
			openFileStatus: 'ready',
			selectedPath: 'docs/plan.md',
			selectedCodeViewItem: {
				id: 'docs-plan',
				type: 'file',
				version: 3,
				file: { name: 'docs/plan.md', contents: '# Plan\n', lang: 'markdown' },
				bridgeMetadata: {
					itemId: 'docs-plan',
					displayPath: 'docs/plan.md',
					contentState: 'hydrated',
					contentRoles: ['file'],
					cacheKey: 'file-cache-key',
					lineCount: 1,
				},
			},
		});

		expect(decision).toMatchObject({
			kind: 'render',
			intent: {
				markdownText: '# Plan\n',
				sourcePath: 'docs/plan.md',
				sourceIdentity: {
					surface: 'file',
					sourceId: 'worktree-1',
					sourceGeneration: 7,
					fileId: 'docs-plan',
					fileVersion: 3,
				},
			},
		});
	});

	test('distinguishes pending Markdown from non-Markdown and incomplete fallbacks', () => {
		expect(
			resolveBridgeFileMarkdownIntent({
				displaySource: { sourceId: 'worktree-1', generation: 7 },
				openFileStatus: 'loading',
				selectedPath: 'README.md',
				selectedCodeViewItem: null,
			}),
		).toEqual({ kind: 'loading' });
		expect(
			resolveBridgeFileMarkdownIntent({
				displaySource: { sourceId: 'worktree-1', generation: 7 },
				openFileStatus: 'ready',
				selectedPath: 'Sources/App.swift',
				selectedCodeViewItem: null,
			}),
		).toEqual({ kind: 'pierre' });
	});

	test('classifies only md extensions as Markdown', () => {
		expect(isMarkdownPath('README.md')).toBe(true);
		expect(isMarkdownPath('docs/PLAN.MD')).toBe(true);
		expect(isMarkdownPath('README.json')).toBe(false);
		expect(isMarkdownPath('docs/readme')).toBe(false);
	});

	test('renders an extensionless file classified as Markdown by the product', () => {
		const decision = resolveBridgeFileMarkdownIntent({
			displaySource: { sourceId: 'worktree-1', generation: 7 },
			openFileStatus: 'ready',
			selectedPath: 'docs/README',
			selectedCodeViewItem: {
				id: 'docs-readme',
				type: 'file',
				version: 1,
				file: { name: 'docs/README', contents: '# Classified Markdown\n', lang: 'markdown' },
				bridgeMetadata: {
					itemId: 'docs-readme',
					displayPath: 'docs/README',
					contentState: 'hydrated',
					contentRoles: ['file'],
					cacheKey: 'classified-markdown-cache-key',
					lineCount: 1,
				},
			},
		});

		expect(decision.kind).toBe('render');
	});
});
