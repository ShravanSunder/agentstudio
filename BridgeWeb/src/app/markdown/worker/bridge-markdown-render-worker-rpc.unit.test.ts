import { describe, expect, test } from 'vitest';

import { buildBridgeMarkdownRenderWorkerSuccessResponse } from './bridge-markdown-render-worker-renderer.js';
import { bridgeMarkdownRenderWorkerRequestSchema } from './bridge-markdown-render-worker-rpc.js';

describe('Bridge markdown render worker RPC', () => {
	test('builds a typed render response with content identity and byte metrics', async () => {
		const request = bridgeMarkdownRenderWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'markdown.render',
			requestId: 'markdown-request-1',
			sourceIdentity: {
				surface: 'file',
				sourceId: 'worktree-1',
				sourceGeneration: 2,
				fileId: 'docs-plan',
				fileVersion: 3,
			},
			contentCacheKey: 'docs-plan:head',
			contentHash: 'sha256:docs-plan:head',
			abortKey: 'bridge-markdown-file',
			markdownText: '# Bridge plan',
			sourcePath: 'docs/plans/bridge.md',
		});

		const response = await buildBridgeMarkdownRenderWorkerSuccessResponse({
			request,
			renderMarkdown: async (markdownText: string) => ({
				htmlCandidate: `<h1>${markdownText.slice(2)}</h1>`,
				mermaidDiagrams: [],
			}),
			now: (() => {
				const samples = [10, 14];
				return (): number => samples.shift() ?? 14;
			})(),
		});

		expect(response).toMatchObject({
			schemaVersion: 1,
			method: 'markdown.render',
			ok: true,
			requestId: 'markdown-request-1',
			sourceIdentity: {
				surface: 'file',
				sourceId: 'worktree-1',
				sourceGeneration: 2,
				fileId: 'docs-plan',
				fileVersion: 3,
			},
			contentCacheKey: 'docs-plan:head',
			contentHash: 'sha256:docs-plan:head',
			htmlCandidate: '<h1>Bridge plan</h1>',
			mermaidDiagrams: [],
			metrics: {
				durationMilliseconds: 4,
				inputBytes: 13,
				outputBytes: 20,
			},
		});
	});

	test('intercepts Mermaid fences without putting diagram source into HTML', async () => {
		const request = bridgeMarkdownRenderWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'markdown.render',
			requestId: 'markdown-request-mermaid',
			sourceIdentity: {
				surface: 'file',
				sourceId: 'worktree-1',
				sourceGeneration: 4,
				fileId: 'docs-plan',
				fileVersion: 2,
			},
			contentCacheKey: 'docs-plan:file',
			contentHash: 'sha256:docs-plan:file',
			markdownText: ['# Bridge plan', '', '```mermaid', 'flowchart LR', 'A --> B', '```'].join(
				'\n',
			),
			sourcePath: 'docs/plans/bridge.md',
		});

		const response = await buildBridgeMarkdownRenderWorkerSuccessResponse({ request });

		expect(response.htmlCandidate).toContain('data-bridge-mermaid-id="mermaid-0"');
		expect(response.htmlCandidate).not.toContain('flowchart LR');
		expect(response.mermaidDiagrams).toEqual([
			{ id: 'mermaid-0', source: 'flowchart LR\nA --> B\n' },
		]);
	});

	test('measures awaited markdown render time', async () => {
		const request = bridgeMarkdownRenderWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'markdown.render',
			requestId: 'markdown-request-1',
			sourceIdentity: {
				surface: 'file',
				sourceId: 'worktree-1',
				sourceGeneration: 2,
				fileId: 'docs-plan',
				fileVersion: 3,
			},
			contentCacheKey: 'docs-plan:head',
			contentHash: 'sha256:docs-plan:head',
			markdownText: '# Bridge plan',
			sourcePath: 'docs/plans/bridge.md',
		});
		let currentTime = 100;

		const response = await buildBridgeMarkdownRenderWorkerSuccessResponse({
			request,
			renderMarkdown: async () => {
				currentTime += 55;
				return { htmlCandidate: '<h1>Bridge plan</h1>', mermaidDiagrams: [] };
			},
			now: (): number => currentTime,
		});

		expect(response.metrics.durationMilliseconds).toBe(55);
	});

	test('default renderer keeps raw HTML and bare URLs inert', async () => {
		const request = bridgeMarkdownRenderWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'markdown.render',
			requestId: 'markdown-request-unsafe',
			sourceIdentity: {
				surface: 'file',
				sourceId: 'worktree-1',
				sourceGeneration: 2,
				fileId: 'docs-plan',
				fileVersion: 3,
			},
			contentCacheKey: 'docs-plan:head',
			contentHash: 'sha256:docs-plan:head',
			markdownText: [
				'# Bridge plan',
				'',
				'<script>alert(1)</script>',
				'',
				'https://example.com/not-a-link',
				'',
				'```ts',
				'const value = 1;',
				'```',
			].join('\n'),
			sourcePath: 'docs/plans/bridge.md',
		});

		const response = await buildBridgeMarkdownRenderWorkerSuccessResponse({ request });

		expect(response.htmlCandidate).toContain('<h1>Bridge plan</h1>');
		expect(response.htmlCandidate).toContain('&lt;script&gt;alert(1)&lt;/script&gt;');
		expect(response.htmlCandidate).not.toContain('<script>');
		expect(response.htmlCandidate).not.toContain('<a href=');
		expect(response.htmlCandidate).toContain('https://example.com/not-a-link');
		expect(response.htmlCandidate).toContain('const');
		expect(response.metrics.inputBytes).toBeGreaterThan(0);
		expect(response.metrics.outputBytes).toBeGreaterThan(0);
	});
});
