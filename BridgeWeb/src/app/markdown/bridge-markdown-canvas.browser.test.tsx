import { afterEach, describe, expect, test, vi } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the product Markdown styles.
import '../bridge-app.css';
import { BridgeMarkdownCanvas } from './bridge-markdown-canvas.js';
import {
	createBridgeMermaidRenderer,
	type BridgeMermaidRenderer,
} from './bridge-mermaid-renderer.js';
import type { BridgeMarkdownPresentationState } from './use-bridge-markdown-presentation.js';

describe('BridgeMarkdownCanvas Browser Mode', () => {
	afterEach(async () => {
		await cleanup();
		document.body.replaceChildren();
	});

	test('renders semantic document structure, inert links, and preserved Shiki colors', async () => {
		await render(
			<BridgeMarkdownCanvas
				presentationState={readyPresentation({
					htmlCandidate: `
						<h1>Markdown proof</h1>
						<p><a href="https://example.com/escape" role="link">Inert reference</a></p>
						<pre class="shiki"><code><span style="color: #ff7b72; background-image: url(https://example.com/x)">let</span> value</code></pre>
						<script>globalThis.markdownScriptExecuted = true</script>
						<img src="https://example.com/tracker.png" />
					`,
				})}
				retry={(): void => {}}
			/>,
		);

		const article = requireHTMLElement(
			document.querySelector('[data-testid="bridge-markdown-canvas"]'),
		);
		const heading = requireHTMLElement(article.querySelector('h1'));
		const link = requireHTMLElement(article.querySelector('a'));
		const highlightedToken = requireHTMLElement(article.querySelector('pre code span'));

		expect(heading.textContent).toBe('Markdown proof');
		expect(link.textContent).toBe('Inert reference');
		expect(link.hasAttribute('href')).toBe(false);
		expect(link.hasAttribute('role')).toBe(false);
		expect(link.classList.contains('bridge-markdown-inert-link')).toBe(true);
		expect(highlightedToken.style.color).not.toBe('');
		expect(highlightedToken.style.backgroundImage).toBe('');
		expect(article.querySelector('script')).toBeNull();
		expect(article.querySelector('img')).toBeNull();
		expect(document.querySelector('[data-testid="bridge-file-viewer-code-view"]')).toBeNull();
	});

	test('lazily renders an admitted Mermaid diagram as labeled sanitized SVG', async () => {
		await render(
			<BridgeMarkdownCanvas
				mermaidRenderer={createBridgeMermaidRenderer()}
				presentationState={readyPresentation({
					htmlCandidate:
						'<div class="bridge-markdown-mermaid" data-bridge-mermaid-id="diagram-0"></div>',
					mermaidDiagrams: [{ id: 'diagram-0', source: 'flowchart LR\nA --> B' }],
				})}
				retry={(): void => {}}
			/>,
		);

		await expect
			.poll(() => document.querySelector('[data-bridge-mermaid-state="ready"] svg'))
			.not.toBeNull();
		const renderedSvg = requireSvgElement(
			document.querySelector('[data-bridge-mermaid-state="ready"] svg'),
		);

		expect(renderedSvg.getAttribute('role')).toBe('img');
		expect(renderedSvg.getAttribute('aria-label')).toBe('Diagram 1 in docs/markdown-proof.md');
		expect(renderedSvg.querySelector('script, foreignObject, image')).toBeNull();
	});

	test('rejects resource-bearing Mermaid before renderer invocation and contains failure locally', async () => {
		const renderDiagram = vi.fn<BridgeMermaidRenderer['render']>();
		await render(
			<BridgeMarkdownCanvas
				mermaidRenderer={{ render: renderDiagram }}
				presentationState={readyPresentation({
					htmlCandidate:
						'<div class="bridge-markdown-mermaid" data-bridge-mermaid-id="diagram-unsafe"></div>',
					mermaidDiagrams: [
						{
							id: 'diagram-unsafe',
							source: 'flowchart LR\nA@{ img: "https://example.com/tracker.png" }',
						},
					],
				})}
				retry={(): void => {}}
			/>,
		);

		await expect
			.poll(() => document.querySelector('[data-bridge-mermaid-state="failed"]'))
			.not.toBeNull();
		expect(renderDiagram).not.toHaveBeenCalled();
		expect(document.body.textContent).toContain('Diagram could not be rendered.');
		expect(document.body.textContent).toContain('Retry diagram');
	});

	test('does not insert a completed diagram into a superseded document', async () => {
		const pendingDiagram = { resolve: null as ((svg: string) => void) | null };
		const mermaidRenderer: BridgeMermaidRenderer = {
			render: () =>
				new Promise<string>((resolve): void => {
					pendingDiagram.resolve = resolve;
				}),
		};
		const rendered = await render(
			<BridgeMarkdownCanvas
				mermaidRenderer={mermaidRenderer}
				presentationState={readyPresentation({
					htmlCandidate:
						'<div class="bridge-markdown-mermaid" data-bridge-mermaid-id="diagram-stale"></div>',
					mermaidDiagrams: [{ id: 'diagram-stale', source: 'flowchart LR\nA --> B' }],
					requestId: 'markdown-request-stale',
				})}
				retry={(): void => {}}
			/>,
		);
		await expect.poll(() => pendingDiagram.resolve).not.toBeNull();

		await rendered.rerender(
			<BridgeMarkdownCanvas
				mermaidRenderer={mermaidRenderer}
				presentationState={readyPresentation({
					htmlCandidate: '<h1>Current document</h1>',
					requestId: 'markdown-request-current',
				})}
				retry={(): void => {}}
			/>,
		);
		if (pendingDiagram.resolve === null) {
			throw new Error('Expected the first Mermaid render to be pending.');
		}
		pendingDiagram.resolve('<svg role="img"><text>Stale diagram</text></svg>');
		await Promise.resolve();

		expect(document.body.textContent).toContain('Current document');
		expect(document.body.textContent).not.toContain('Stale diagram');
		expect(document.querySelector('[data-bridge-mermaid-id="diagram-stale"]')).toBeNull();
	});
});

function readyPresentation(props: {
	readonly htmlCandidate: string;
	readonly mermaidDiagrams?: readonly { readonly id: string; readonly source: string }[];
	readonly requestId?: string;
}): Extract<BridgeMarkdownPresentationState, { readonly status: 'ready' }> {
	const requestId = props.requestId ?? 'markdown-request-browser';
	const identity = {
		requestId,
		sourceIdentity: {
			surface: 'file' as const,
			sourceId: 'worktree-source',
			sourceGeneration: 1,
			fileId: 'markdown-proof',
			fileVersion: 1,
		},
		contentCacheKey: 'markdown-proof-cache',
		contentHash: 'markdown-proof-hash',
		abortKey: 'bridge-markdown-file',
	};
	return {
		status: 'ready',
		sourcePath: 'docs/markdown-proof.md',
		identity,
		renderResult: {
			schemaVersion: 1,
			method: 'markdown.render',
			ok: true,
			...identity,
			htmlCandidate: props.htmlCandidate,
			mermaidDiagrams: [...(props.mermaidDiagrams ?? [])],
			metrics: {
				durationMilliseconds: 1,
				inputBytes: 1,
				outputBytes: props.htmlCandidate.length,
				mermaidDiagramCount: props.mermaidDiagrams?.length ?? 0,
			},
		},
	};
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) {
		throw new Error('Expected an HTMLElement.');
	}
	return element;
}

function requireSvgElement(element: Element | null): SVGElement {
	if (!(element instanceof SVGElement)) {
		throw new Error('Expected an SVGElement.');
	}
	return element;
}
