import { afterAll, afterEach, beforeEach, describe, expect, test, vi } from 'vitest';
import { cleanup, render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the product Markdown styles.
import '../app/bridge-app.css';
import { createBridgeMermaidRenderer } from '../app/markdown/bridge-mermaid-renderer.js';
import {
	createBridgeMarkdownRenderWorkerClient,
	type BridgeMarkdownRenderWorkerTransport,
} from '../app/markdown/worker/bridge-markdown-render-worker-client.js';
import {
	identityFromMarkdownRenderWorkerRequest,
	type BridgeMarkdownRenderWorkerRequest,
} from '../app/markdown/worker/bridge-markdown-render-worker-rpc.js';
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

			await waitForMarkdownOpenFileState('ready');
			await waitForMarkdownSelector('[data-testid="bridge-markdown-canvas"] h1');
			await waitForMarkdownSelector('[data-bridge-mermaid-state="ready"] svg');

			const markdownCanvas = requireHTMLElement(
				document.querySelector('[data-testid="bridge-markdown-canvas"]'),
			);
			const inertLink = requireHTMLElement(markdownCanvas.querySelector('a'));
			const codeBlock = requireHTMLElement(markdownCanvas.querySelector('pre'));
			const swiftCode = requireHTMLElement(codeBlock.querySelector('code'));
			const highlightedTokens = Array.from(
				markdownCanvas.querySelectorAll<HTMLElement>('pre code span[style*="color"]'),
			);
			const highlightedColors = new Set(
				highlightedTokens
					.map((token): string => token.style.color)
					.filter((color): boolean => color.length > 0),
			);
			const diagram = markdownCanvas.querySelector('svg[role="img"]');

			expect(markdownCanvas.textContent).toContain('File Markdown proof');
			expect(markdownCanvas.querySelector('blockquote')).not.toBeNull();
			expect(markdownCanvas.querySelector('ul')).not.toBeNull();
			expect(markdownCanvas.querySelector('table')).not.toBeNull();
			expect(markdownCanvas.querySelector('th')?.textContent).toBe('Surface');
			expect(markdownCanvas.querySelector('td')?.textContent).toBe('File');
			expect(inertLink.hasAttribute('href')).toBe(false);
			expect(swiftCode.textContent).toContain('let markdownProof: String');
			expect(highlightedColors.size).toBeGreaterThan(1);
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
			await waitForMarkdownOpenFileState('ready');
			await waitForMarkdownSelector('[data-bridge-mermaid-state="ready"] svg');
			const originalCanvas = requireHTMLElement(
				document.querySelector('[data-testid="bridge-markdown-canvas"]'),
			);
			const originalSvg = originalCanvas.querySelector('svg');
			const markdownScrollOwner = originalCanvas.parentElement;
			if (!(markdownScrollOwner instanceof HTMLElement)) {
				throw new Error('Expected the Markdown scroll owner.');
			}

			const searchToggle = requireHTMLElement(
				document.querySelector('[data-testid="worktree-file-search-toggle"]'),
			);
			await actClick(searchToggle);
			await actClick(searchToggle);
			await actFrame();

			expect(document.querySelector('[data-testid="bridge-markdown-canvas"]')).toBe(originalCanvas);
			expect(originalCanvas.parentElement).toBe(markdownScrollOwner);
			expect(originalCanvas.querySelector('svg')).toBe(originalSvg);
			expect(originalCanvas.querySelector('[data-bridge-mermaid-state="ready"]')).not.toBeNull();
			expect(document.querySelector('[data-testid="bridge-markdown-status"]')).toBeNull();
		} finally {
			markdownWorkerClient.dispose();
		}
	});

	test('aborts in-flight Markdown preparation when retained File view becomes inactive', async () => {
		const markdownContent = '# Suspended Markdown\n';
		const markdownDescriptor = await makeFileDescriptorForContent({
			content: markdownContent,
			contentHandle: 'suspended-markdown-content',
			fileId: 'suspended-markdown',
			path: 'docs/suspended.md',
		});
		const sendRenderRequest = vi.fn<BridgeMarkdownRenderWorkerTransport['send']>(
			(): Promise<unknown> => new Promise<unknown>(() => {}),
		);
		const abortRenderRequest = vi.fn<NonNullable<BridgeMarkdownRenderWorkerTransport['abort']>>();
		const markdownWorkerClient = createBridgeMarkdownRenderWorkerClient({
			transport: { send: sendRenderRequest, abort: abortRenderRequest },
		});
		const activeApp = (
			<BridgeFileViewerApp
				codeViewWorkerPoolEnabled={false}
				initialMetadataEvents={makeFileMetadataEvents(markdownDescriptor)}
				isActive={true}
				markdownWorkerClient={markdownWorkerClient}
				navigationCommand={fileNavigationCommandForPath('docs/suspended.md')}
				fileProductSession={{ readContent: async (): Promise<string> => markdownContent }}
			/>
		);

		try {
			const rendered = await render(activeApp);
			await waitForMarkdownOpenFileState('ready');
			await waitForMarkdownSelector('[data-testid="bridge-markdown-status"]');
			expect(sendRenderRequest).toHaveBeenCalledOnce();

			await rendered.rerender(
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					initialMetadataEvents={makeFileMetadataEvents(markdownDescriptor)}
					isActive={false}
					markdownWorkerClient={markdownWorkerClient}
					navigationCommand={fileNavigationCommandForPath('docs/suspended.md')}
					fileProductSession={{ readContent: async (): Promise<string> => markdownContent }}
				/>,
			);

			expect(abortRenderRequest).toHaveBeenCalledOnce();
			expect(sendRenderRequest).toHaveBeenCalledOnce();
		} finally {
			markdownWorkerClient.dispose();
		}
	});

	test('recovers a failed File Markdown render through the visible Retry action', async () => {
		// Arrange
		const markdownContent = '# Retry Markdown\n';
		const markdownDescriptor = await makeFileDescriptorForContent({
			content: markdownContent,
			contentHandle: 'retry-markdown-content',
			fileId: 'retry-markdown',
			path: 'docs/retry.md',
		});
		let sendCount = 0;
		const transport: BridgeMarkdownRenderWorkerTransport = {
			send: async (request: BridgeMarkdownRenderWorkerRequest): Promise<unknown> => {
				sendCount += 1;
				if (sendCount === 1) {
					throw new Error('Expected first render failure');
				}
				return {
					schemaVersion: 1,
					method: request.method,
					ok: true,
					...identityFromMarkdownRenderWorkerRequest(request),
					htmlCandidate: '<h1>Recovered Markdown</h1>',
					mermaidDiagrams: [],
					metrics: {
						durationMilliseconds: 1,
						inputBytes: markdownContent.length,
						outputBytes: 27,
						mermaidDiagramCount: 0,
					},
				};
			},
		};
		const markdownWorkerClient = createBridgeMarkdownRenderWorkerClient({
			transport,
			createRequestId: (): string => `retry-${(sendCount + 1).toString()}`,
		});

		try {
			await render(
				<BridgeFileViewerApp
					codeViewWorkerPoolEnabled={false}
					initialMetadataEvents={makeFileMetadataEvents(markdownDescriptor)}
					markdownWorkerClient={markdownWorkerClient}
					navigationCommand={fileNavigationCommandForPath('docs/retry.md')}
					fileProductSession={{ readContent: async (): Promise<string> => markdownContent }}
				/>,
			);
			await waitForMarkdownOpenFileState('ready');
			await waitForMarkdownSelector('[role="alert"]');

			// Act
			const retryButton = requireHTMLElement(document.querySelector('[role="alert"] button'));
			await actClick(retryButton);

			// Assert
			await waitForMarkdownSelector('[data-testid="bridge-markdown-canvas"] h1');
			expect(document.querySelector('[data-testid="bridge-markdown-canvas"] h1')?.textContent).toBe(
				'Recovered Markdown',
			);
			expect(document.querySelector('[role="alert"]')).toBeNull();
			expect(sendCount).toBe(2);
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

async function waitForMarkdownOpenFileState(expectedState: string): Promise<void> {
	const currentState = document
		.querySelector('[data-worktree-open-file-state]')
		?.getAttribute('data-worktree-open-file-state');
	if (currentState === expectedState) return;
	await actFrame();
	await waitForMarkdownOpenFileState(expectedState);
}

async function waitForMarkdownSelector(selector: string): Promise<void> {
	if (document.querySelector(selector) !== null) {
		return;
	}
	const terminalFailure =
		selector === '[role="alert"]'
			? null
			: (document.querySelector('[role="alert"]')?.textContent ??
				document.querySelector('[data-bridge-mermaid-state="failed"]')?.textContent);
	if (terminalFailure !== null && terminalFailure !== undefined) {
		throw new Error(
			`Expected Markdown selector to appear: ${selector}; terminal failure: ${terminalFailure}`,
		);
	}
	await actFrame();
	await waitForMarkdownSelector(selector);
}
