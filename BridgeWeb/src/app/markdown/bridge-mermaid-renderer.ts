import DOMPurify from 'dompurify';

export const bridgeMermaidPolicy = {
	maxDiagramCount: 12,
	maxDiagramSourceBytes: 48 * 1024,
	maxDocumentDiagramSourceBytes: 144 * 1024,
	maxEdges: 500,
	maxTextSize: 48 * 1024,
} as const;

export type BridgeMermaidSourceAdmission =
	| { readonly admitted: true }
	| { readonly admitted: false; readonly reason: 'tooLarge' | 'unsafeSource' };

export interface BridgeMermaidRenderer {
	readonly render: (props: {
		readonly diagramId: string;
		readonly source: string;
		readonly accessibleLabel: string;
	}) => Promise<string>;
}

let sharedInitializedMermaidPromise: Promise<(typeof import('mermaid'))['default']> | null = null;

async function sharedInitializedMermaid(): Promise<(typeof import('mermaid'))['default']> {
	sharedInitializedMermaidPromise ??= import('mermaid').then(({ default: mermaid }) => {
		mermaid.initialize({
			startOnLoad: false,
			securityLevel: 'strict',
			htmlLabels: false,
			suppressErrorRendering: true,
			theme: 'dark',
			maxTextSize: bridgeMermaidPolicy.maxTextSize,
			maxEdges: bridgeMermaidPolicy.maxEdges,
			flowchart: { htmlLabels: false },
			secure: [
				'securityLevel',
				'startOnLoad',
				'maxTextSize',
				'maxEdges',
				'suppressErrorRendering',
				'htmlLabels',
				'theme',
				'themeCSS',
				'themeVariables',
				'fontFamily',
				'altFontFamily',
			],
		});
		return mermaid;
	});
	return await sharedInitializedMermaidPromise;
}

export function createBridgeMermaidRenderer(): BridgeMermaidRenderer {
	return {
		render: async (props): Promise<string> => {
			const admission = bridgeMermaidSourceAdmission(props.source);
			if (!admission.admitted) {
				throw new Error(`Mermaid source rejected: ${admission.reason}`);
			}
			const mermaid = await sharedInitializedMermaid();
			const { svg } = await mermaid.render(props.diagramId, props.source);
			return addBridgeMermaidAccessibleLabel(sanitizeBridgeMermaidSvg(svg), props.accessibleLabel);
		},
	};
}

export function bridgeMermaidSourceAdmission(source: string): BridgeMermaidSourceAdmission {
	if (new TextEncoder().encode(source).byteLength > bridgeMermaidPolicy.maxDiagramSourceBytes) {
		return { admitted: false, reason: 'tooLarge' };
	}
	const unsafePatterns = [
		/%%\s*\{/iu,
		/^\s*(?:classDef|style|linkStyle|click)\b/imu,
		/\b(?:image|icon|img)\s*:/iu,
		/(?:https?|data|blob|file):/iu,
		/url\s*\(/iu,
		/@(?:import|font-face|supports|document|namespace)\b/iu,
	];
	return unsafePatterns.some((pattern): boolean => pattern.test(source))
		? { admitted: false, reason: 'unsafeSource' }
		: { admitted: true };
}

export function sanitizeBridgeMermaidSvg(svgCandidate: string): string {
	const domPurifiedSvg =
		typeof DOMPurify.sanitize === 'function'
			? DOMPurify.sanitize(svgCandidate, {
					USE_PROFILES: { svg: true, svgFilters: true },
					ADD_TAGS: ['style'],
					FORBID_TAGS: ['script', 'foreignObject', 'iframe', 'object', 'embed', 'image'],
					FORBID_ATTR: ['onclick', 'onload', 'onerror', 'href', 'xlink:href'],
				})
			: svgCandidate;
	return stripUnsafeBridgeMermaidSvgContent(domPurifiedSvg);
}

function stripUnsafeBridgeMermaidSvgContent(svg: string): string {
	let sanitizedSvg = svg
		.replace(
			/<(?:script|foreignObject|iframe|object|embed|image)\b[^>]*>[\s\S]*?<\/(?:script|foreignObject|iframe|object|embed|image)>/giu,
			'',
		)
		.replace(/<(?:script|foreignObject|iframe|object|embed|image)\b[^>]*\/?\s*>/giu, '')
		.replace(/\s(?:on[a-z]+|href|xlink:href)\s*=\s*(?:"[^"]*"|'[^']*')/giu, '');
	sanitizedSvg = sanitizedSvg.replace(/<style\b[^>]*>([\s\S]*?)<\/style>/giu, (styleTag, css) =>
		bridgeMermaidCssIsSafe(css) ? styleTag : '',
	);
	return sanitizedSvg.replace(
		/\s(?:fill|stroke|filter|marker-start|marker-mid|marker-end)\s*=\s*(["'])(url\([^)]*\))\1/giu,
		(attribute, _quote, urlValue) => (/^url\(#[a-z_][\w:.-]*\)$/iu.test(urlValue) ? attribute : ''),
	);
}

function bridgeMermaidCssIsSafe(css: string): boolean {
	if (/@(?:import|font-face|supports|document|namespace)\b/iu.test(css)) {
		return false;
	}
	for (const match of css.matchAll(/url\(([^)]*)\)/giu)) {
		const urlValue = match[1]?.trim().replace(/^['"]|['"]$/gu, '') ?? '';
		if (!/^#[a-z_][\w:.-]*$/iu.test(urlValue)) {
			return false;
		}
	}
	return !/(?:https?|data|blob|file):/iu.test(css);
}

function addBridgeMermaidAccessibleLabel(svg: string, accessibleLabel: string): string {
	const safeLabel = escapeHtmlAttribute(accessibleLabel);
	return svg.replace(/<svg\b/iu, `<svg role="img" aria-label="${safeLabel}"`);
}

function escapeHtmlAttribute(value: string): string {
	return value
		.replaceAll('&', '&amp;')
		.replaceAll('"', '&quot;')
		.replaceAll('<', '&lt;')
		.replaceAll('>', '&gt;');
}
