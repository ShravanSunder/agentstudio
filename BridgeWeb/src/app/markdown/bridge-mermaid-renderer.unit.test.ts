import { afterEach, describe, expect, test, vi } from 'vitest';

import {
	bridgeMermaidSourceAdmission,
	sanitizeBridgeMermaidSvg,
} from './bridge-mermaid-renderer.js';

describe('Bridge Mermaid trust boundary', () => {
	afterEach(() => {
		vi.doUnmock('mermaid');
		vi.resetModules();
	});

	test('admits inert diagrams and rejects configuration, interaction, style, and resources', () => {
		expect(bridgeMermaidSourceAdmission('flowchart LR\nA --> B')).toEqual({ admitted: true });
		for (const source of [
			'%%{init: {"themeCSS":"@import url(https://example.com/x.css)"}}%%\nflowchart LR',
			'flowchart LR\nclick A "https://example.com"',
			'flowchart LR\nclassDef danger fill:url(https://example.com/x)',
			'flowchart LR\nstyle A fill:#fff',
			'flowchart LR\nA@{ img: "data:image/svg+xml;base64,PHN2Zy8+" }',
		]) {
			expect(bridgeMermaidSourceAdmission(source)).toMatchObject({ admitted: false });
		}
	});

	test('keeps inert SVG and same-document markers but removes executable and remote content', () => {
		const sanitizedSvg = sanitizeBridgeMermaidSvg(`
			<svg xmlns="http://www.w3.org/2000/svg" onclick="alert(1)">
				<style>@import url(https://example.com/x.css); .edge { marker-end: url(#arrow); }</style>
				<script>alert(1)</script>
				<foreignObject><div>active</div></foreignObject>
				<image href="https://example.com/x.png" />
				<defs><marker id="arrow"></marker></defs>
				<path class="edge" marker-end="url(#arrow)" d="M0 0L1 1" />
			</svg>
		`);

		expect(sanitizedSvg).not.toMatch(/script|foreignObject|image|onclick|example\.com|@import/iu);
		expect(sanitizedSvg).toContain('url(#arrow)');
	});

	test('retries Mermaid bootstrap after the first initialization rejects', async () => {
		vi.resetModules();
		let initializeAttemptCount = 0;
		vi.doMock('mermaid', () => ({
			default: {
				initialize: (): void => {
					initializeAttemptCount += 1;
					if (initializeAttemptCount === 1) {
						throw new Error('Mermaid initialization failed');
					}
				},
				render: async (): Promise<{ readonly svg: string }> => ({
					svg: '<svg><text>Recovered diagram</text></svg>',
				}),
			},
		}));
		const { createBridgeMermaidRenderer } = await import('./bridge-mermaid-renderer.js');
		const renderer = createBridgeMermaidRenderer();
		const renderProps = {
			diagramId: 'retry-diagram',
			source: 'flowchart LR\nA --> B',
			accessibleLabel: 'Recovered diagram',
		} as const;

		await expect(renderer.render(renderProps)).rejects.toThrow('Mermaid initialization failed');
		await expect(renderer.render(renderProps)).resolves.toContain('Recovered diagram');
		expect(initializeAttemptCount).toBe(2);
	});
});
