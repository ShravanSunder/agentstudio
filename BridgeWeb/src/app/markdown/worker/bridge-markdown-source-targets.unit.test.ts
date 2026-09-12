import { describe, expect, test } from 'vitest';

import { bridgeMarkdownSourceTargetsSchema } from '../bridge-markdown-source-target.js';
import { buildBridgeMarkdownRenderWorkerSuccessResponse } from './bridge-markdown-render-worker-renderer.js';
import {
	bridgeMarkdownRenderWorkerRequestSchema,
	type BridgeMarkdownRenderWorkerSuccessResponse,
} from './bridge-markdown-render-worker-rpc.js';

describe('Markdown source targets', () => {
	test('rejects ambiguous and reversed catalogs', () => {
		const target = { id: 'paragraph', kind: 'prose', block: 'paragraph', startLine: 1, endLine: 2 };
		expect(bridgeMarkdownSourceTargetsSchema.safeParse([target, target]).success).toBe(false);
		expect(bridgeMarkdownSourceTargetsSchema.safeParse([{ ...target, endLine: 0 }]).success).toBe(
			false,
		);
		expect(
			bridgeMarkdownSourceTargetsSchema.safeParse([
				target,
				{ ...target, id: 'nested', startLine: 2, endLine: 3 },
			]).success,
		).toBe(false);
	});

	test('maps indented code and normalizes CRLF without shifting source lines', async () => {
		const response = await renderSource(['Text\r', '\r', '    first\r', '    second\r']);
		expect(response.annotationTargets).toMatchObject([
			{ kind: 'prose', startLine: 1, endLine: 1 },
			{ kind: 'code-block', startLine: 3, endLine: 4 },
		]);
	});
	test('maps each list paragraph without its descendants and maps table rows', async () => {
		const response = await renderSource([
			'# Plan',
			'',
			'- [ ] Parent',
			'  - [x] Child',
			'    - Grandchild',
			'',
			'| Name | State |',
			'| --- | --- |',
			'| App | Ready |',
			'',
			'> Quoted **text**',
			'> continued',
		]);
		expect(response).toMatchObject({
			annotationTargets: [
				{ kind: 'prose', startLine: 1, endLine: 1 },
				{ kind: 'prose', startLine: 3, endLine: 3 },
				{ kind: 'prose', startLine: 4, endLine: 4 },
				{ kind: 'prose', startLine: 5, endLine: 5 },
				{ kind: 'table-row', startLine: 7, endLine: 7 },
				{ kind: 'table-row', startLine: 9, endLine: 9 },
				{ kind: 'prose', startLine: 11, endLine: 12 },
			],
		});
		expect(response.htmlCandidate).toContain('data-bridge-markdown-target=');
		expect(response.htmlCandidate).not.toContain('<input');
	});

	test('maps logical fence lines including blanks and whole Mermaid and empty fences', async () => {
		const response = await renderSource([
			'```ts',
			'const ready = true;',
			'',
			'await deploy();',
			'```',
			'',
			'```mermaid',
			'flowchart LR',
			'A --> B',
			'```',
			'',
			'```text',
			'```',
		]);
		expect(response).toMatchObject({
			annotationTargets: [
				{ kind: 'code-line', startLine: 2, endLine: 2 },
				{ kind: 'code-line', startLine: 3, endLine: 3 },
				{ kind: 'code-line', startLine: 4, endLine: 4 },
				{ kind: 'diagram', startLine: 7, endLine: 10 },
				{ kind: 'code-block', startLine: 12, endLine: 13 },
			],
		});
		expect(response.htmlCandidate).not.toContain('flowchart LR');
	});
});

async function renderSource(
	lines: readonly string[],
): Promise<BridgeMarkdownRenderWorkerSuccessResponse> {
	return await buildBridgeMarkdownRenderWorkerSuccessResponse({
		request: bridgeMarkdownRenderWorkerRequestSchema.parse({
			schemaVersion: 1,
			method: 'markdown.render',
			requestId: 'source-target-test',
			sourceIdentity: {
				surface: 'file',
				sourceId: 'worktree',
				sourceGeneration: 1,
				fileId: 'plan',
				fileVersion: 1,
			},
			contentCacheKey: 'plan:1',
			contentHash: 'plan:1',
			sourcePath: 'plan.md',
			markdownText: lines.join('\n'),
		}),
	});
}
