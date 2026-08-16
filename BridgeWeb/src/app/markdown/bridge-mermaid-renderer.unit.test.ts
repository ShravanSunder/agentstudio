import { describe, expect, test } from 'vitest';

import {
	bridgeMermaidSourceAdmission,
	sanitizeBridgeMermaidSvg,
} from './bridge-mermaid-renderer.js';

describe('Bridge Mermaid trust boundary', () => {
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
});
