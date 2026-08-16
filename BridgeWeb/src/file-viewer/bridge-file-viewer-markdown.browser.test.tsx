import { afterAll, afterEach, beforeEach, describe, expect, test } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the product Markdown styles.
import '../app/bridge-app.css';
import { createBridgeMermaidRenderer } from '../app/markdown/bridge-mermaid-renderer.js';
import {
	createBridgeMarkdownRenderModuleWorkerFactory,
	createBridgeMarkdownRenderWebWorkerClient,
} from '../app/markdown/worker/bridge-markdown-render-worker-transport.js';
import { terminateBridgePierreWorkerPoolSingletonForTest } from '../review-viewer/workers/pierre/bridge-pierre-worker-pool.js';
import { BridgeFileViewerBrowserHarnessApp as BridgeFileViewerApp } from './bridge-file-viewer-browser-test-app.js';
import {
	fileNavigationCommandForPath,
	makeFileDescriptorForContent,
	makeFileMetadataEvents,
} from './bridge-file-viewer-browser-test-fixtures.js';
import {
	actFrame,
	actClick,
	actUpdate,
	installBridgeFileViewerNoopResizeObserver,
	waitForOpenFileState,
} from './bridge-file-viewer-browser-test-harness.js';

const originalResizeObserver = globalThis.ResizeObserver;

describe('BridgeFileViewerApp Markdown Browser Mode', () => {
	beforeEach(() => {
		installBridgeFileViewerNoopResizeObserver();
	});

	afterEach(async () => {
		await actUpdate(async (): Promise<void> => cleanup());
		await actFrame();
		document.body.replaceChildren();
		terminateBridgePierreWorkerPoolSingletonForTest();
	});

	afterAll(() => {
		Object.assign(globalThis, { ResizeObserver: originalResizeObserver });
	});

	test('mounts the complete semantic Markdown document instead of Pierre', async () => {
		const markdownContent = [
			'# File Markdown proof',
			'',
			'> Complete current document',
			'',
			'- Heading',
			'- List',
			'',
			'| Surface | Projection |',
			'| --- | --- |',
			'| File | Rendered |',
			'',
			'[Inert reference](https://example.com/escape)',
			'',
			'```swift',
			'let markdownProof: String = "This intentionally long Swift line proves horizontal code overflow rather than wrapping the source text."',
			'```',
			'',
			'```mermaid',
			'flowchart LR',
			'File --> Markdown',
			'```',
			'',
		].join('\n');
		const markdownDescriptor = await makeFileDescriptorForContent({
			content: markdownContent,
			contentHandle: 'file-markdown-browser-content',
			fileId: 'file-markdown-browser',
			path: 'docs/markdown-proof.md',
		});
		const markdownWorkerClient = createBridgeMarkdownRenderWebWorkerClient({
			workerFactory: createBridgeMarkdownRenderModuleWorkerFactory(),
		});
		if (markdownWorkerClient === null) {
			throw new Error('Expected Browser Mode to support the Markdown worker.');
		}

		try {
			await render(
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					initialMetadataEvents={makeFileMetadataEvents(markdownDescriptor)}
					markdownWorkerClient={markdownWorkerClient}
					mermaidRenderer={createBridgeMermaidRenderer()}
					navigationCommand={fileNavigationCommandForPath('docs/markdown-proof.md')}
					fileProductSession={{ readContent: async (): Promise<string> => markdownContent }}
				/>,
			);

			await waitForOpenFileState('ready');
			await waitForMarkdownSelector('[data-testid="bridge-markdown-canvas"] h1');
			await waitForMarkdownSelector('[data-bridge-mermaid-state="ready"] svg');

			const markdownCanvas = requireHTMLElement(
				document.querySelector('[data-testid="bridge-markdown-canvas"]'),
			);
			const inertLink = requireHTMLElement(markdownCanvas.querySelector('a'));
			const codeBlock = requireHTMLElement(markdownCanvas.querySelector('pre'));
			const highlightedTokens = markdownCanvas.querySelectorAll('pre code span[style*="color"]');
			const diagram = markdownCanvas.querySelector('svg[role="img"]');

			expect(markdownCanvas.textContent).toContain('File Markdown proof');
			expect(markdownCanvas.querySelector('blockquote')).not.toBeNull();
			expect(markdownCanvas.querySelector('ul')).not.toBeNull();
			expect(markdownCanvas.querySelector('table')).not.toBeNull();
			expect(inertLink.hasAttribute('href')).toBe(false);
			expect(highlightedTokens.length).toBeGreaterThan(1);
			expect(getComputedStyle(codeBlock).overflowX).toBe('auto');
			expect(diagram?.getAttribute('aria-label')).toBe('Diagram 1 in docs/markdown-proof.md');
			expect(document.querySelector('[data-testid="bridge-file-viewer-code-view"]')).toBeNull();
		} finally {
			markdownWorkerClient.dispose();
		}
	});

	test('preserves the rendered document and Mermaid SVG across File search rerenders', async () => {
		const markdownContent =
			'# Stable Markdown\n\n```mermaid\nflowchart LR\nFile --> Markdown\n```\n';
		const markdownDescriptor = await makeFileDescriptorForContent({
			content: markdownContent,
			contentHandle: 'stable-markdown-content',
			fileId: 'stable-markdown',
			path: 'docs/stable.md',
		});
		const markdownWorkerClient = createBridgeMarkdownRenderWebWorkerClient({
			workerFactory: createBridgeMarkdownRenderModuleWorkerFactory(),
		});
		if (markdownWorkerClient === null) throw new Error('expected markdown worker client');

		try {
			await render(
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					initialMetadataEvents={makeFileMetadataEvents(markdownDescriptor)}
					markdownWorkerClient={markdownWorkerClient}
					mermaidRenderer={createBridgeMermaidRenderer()}
					navigationCommand={fileNavigationCommandForPath('docs/stable.md')}
					fileProductSession={{ readContent: async (): Promise<string> => markdownContent }}
				/>,
			);
			await waitForOpenFileState('ready');
			await waitForMarkdownSelector('[data-bridge-mermaid-state="ready"] svg');
			const originalCanvas = requireHTMLElement(
				document.querySelector('[data-testid="bridge-markdown-canvas"]'),
			);
			const originalSvg = originalCanvas.querySelector('svg');
			originalCanvas.parentElement?.scrollTo({ top: 12 });

			const searchToggle = requireHTMLElement(
				document.querySelector('[data-testid="worktree-file-search-toggle"]'),
			);
			await actClick(searchToggle);
			await actClick(searchToggle);
			await actFrame();

			expect(document.querySelector('[data-testid="bridge-markdown-canvas"]')).toBe(originalCanvas);
			expect(originalCanvas.querySelector('svg')).toBe(originalSvg);
			expect(originalCanvas.querySelector('[data-bridge-mermaid-state="ready"]')).not.toBeNull();
			expect(document.querySelector('[data-testid="bridge-markdown-status"]')).toBeNull();
		} finally {
			markdownWorkerClient.dispose();
		}
	});
});

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) {
		throw new Error('Expected an HTMLElement.');
	}
	return element;
}

async function waitForMarkdownSelector(selector: string, attempt = 0): Promise<void> {
	if (document.querySelector(selector) !== null) {
		return;
	}
	if (attempt >= 60) {
		throw new Error(`Expected Markdown selector to appear: ${selector}`);
	}
	await actFrame();
	await waitForMarkdownSelector(selector, attempt + 1);
}
