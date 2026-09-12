import { createMarkdownExit } from 'markdown-exit';
import { createHighlighterCore, type HighlighterCore } from 'shiki/core';
import { createJavaScriptRegexEngine } from 'shiki/engine/javascript';
import cssLanguage from 'shiki/langs/css.mjs';
import diffLanguage from 'shiki/langs/diff.mjs';
import htmlLanguage from 'shiki/langs/html.mjs';
import javascriptLanguage from 'shiki/langs/javascript.mjs';
import jsonLanguage from 'shiki/langs/json.mjs';
import jsoncLanguage from 'shiki/langs/jsonc.mjs';
import markdownLanguage from 'shiki/langs/md.mjs';
import shellLanguage from 'shiki/langs/shellscript.mjs';
import swiftLanguage from 'shiki/langs/swift.mjs';
import tsxLanguage from 'shiki/langs/tsx.mjs';
import typescriptLanguage from 'shiki/langs/typescript.mjs';
import yamlLanguage from 'shiki/langs/yaml.mjs';
import githubDarkTheme from 'shiki/themes/github-dark.mjs';

import type { BridgeMarkdownSourceTarget } from '../bridge-markdown-source-target.js';
import { annotateMarkdownBlockTokens } from './bridge-markdown-block-targets.js';

export type BridgeMarkdownRenderer = ReturnType<typeof createMarkdownExit>;
export type BridgeMarkdownTokens = ReturnType<BridgeMarkdownRenderer['parse']>;
import {
	bridgeMarkdownRenderWorkerSuccessResponseSchema,
	identityFromMarkdownRenderWorkerRequest,
	type BridgeMarkdownMermaidDiagram,
	type BridgeMarkdownRenderWorkerRequest,
	type BridgeMarkdownRenderWorkerSuccessResponse,
} from './bridge-markdown-render-worker-rpc.js';

interface BridgeMarkdownRenderOutput {
	readonly htmlCandidate: string;
	readonly annotationTargets: readonly BridgeMarkdownSourceTarget[];
	readonly mermaidDiagrams: readonly BridgeMarkdownMermaidDiagram[];
}

export interface BuildBridgeMarkdownRenderWorkerSuccessResponseProps {
	readonly request: BridgeMarkdownRenderWorkerRequest;
	readonly renderMarkdown?: (markdownText: string) => Promise<BridgeMarkdownRenderOutput>;
	readonly now?: () => number;
}

export async function buildBridgeMarkdownRenderWorkerSuccessResponse(
	props: BuildBridgeMarkdownRenderWorkerSuccessResponseProps,
): Promise<BridgeMarkdownRenderWorkerSuccessResponse> {
	const renderMarkdown = props.renderMarkdown ?? renderBridgeMarkdown;
	const now = props.now ?? performance.now.bind(performance);
	const start = now();
	const renderOutput = await renderMarkdown(props.request.markdownText);
	const durationMilliseconds = Math.max(0, now() - start);
	const response = {
		schemaVersion: 1,
		method: props.request.method,
		ok: true,
		...identityFromMarkdownRenderWorkerRequest(props.request),
		htmlCandidate: renderOutput.htmlCandidate,
		annotationTargets: [...renderOutput.annotationTargets],
		mermaidDiagrams: [...renderOutput.mermaidDiagrams],
		metrics: {
			durationMilliseconds,
			inputBytes: byteLength(props.request.markdownText),
			outputBytes: byteLength(renderOutput.htmlCandidate),
			mermaidDiagramCount: renderOutput.mermaidDiagrams.length,
		},
	} satisfies BridgeMarkdownRenderWorkerSuccessResponse;

	return bridgeMarkdownRenderWorkerSuccessResponseSchema.parse(response);
}

const bridgeMarkdownHighlighterPromise = createHighlighterCore({
	themes: [githubDarkTheme],
	langs: [
		...cssLanguage,
		...diffLanguage,
		...htmlLanguage,
		...javascriptLanguage,
		...jsonLanguage,
		...jsoncLanguage,
		...markdownLanguage,
		...shellLanguage,
		...swiftLanguage,
		...tsxLanguage,
		...typescriptLanguage,
		...yamlLanguage,
	],
	engine: createJavaScriptRegexEngine(),
});

async function renderBridgeMarkdown(markdownText: string): Promise<BridgeMarkdownRenderOutput> {
	const markdownRenderer = createMarkdownExit('default', {
		html: false,
		linkify: false,
		typographer: false,
	});
	const annotationTargets: BridgeMarkdownSourceTarget[] = [];
	const mermaidDiagrams: BridgeMarkdownMermaidDiagram[] = [];
	const highlighter = await bridgeMarkdownHighlighterPromise;
	markdownRenderer.renderer.rules.fence = async (tokens, index): Promise<string> => {
		const token = tokens[index];
		if (token?.map === null || token === undefined)
			throw new Error('Missing Markdown fence source map');
		const range = { startLine: token.map[0] + 1, endLine: token.map[1] };
		const fenceId = `fence-${range.startLine}`;
		const language = normalizedFenceLanguage(token.info);
		if (language === 'mermaid') {
			const id = `mermaid-${mermaidDiagrams.length.toString()}`;
			mermaidDiagrams.push({ id, source: token.content });
			annotationTargets.push({ kind: 'diagram', id: fenceId, ...range });
			return `<div class="bridge-markdown-mermaid" data-bridge-mermaid-id="${id}" data-bridge-markdown-target="${fenceId}"></div>`;
		}
		if (token.content.length === 0) {
			annotationTargets.push({ kind: 'code-block', id: fenceId, ...range });
			return `<div class="bridge-markdown-code-block" data-bridge-markdown-target="${fenceId}"><code></code></div>`;
		}
		const code = token.content.endsWith('\n') ? token.content.slice(0, -1) : token.content;
		return highlighter.codeToHtml(code, {
			lang: supportedMarkdownLanguage(highlighter, language),
			theme: 'github-dark',
			transformers: [
				{
					pre(node): void {
						node.tagName = 'div';
						node.properties['class'] = 'bridge-markdown-code-block';
						delete node.properties['style'];
					},
					code(node): void {
						node.tagName = 'div';
						node.properties['class'] = 'bridge-markdown-code-lines';
					},
					line(node, ordinal): void {
						const sourceLine = range.startLine + ordinal;
						const id = `${fenceId}-line-${ordinal}`;
						annotationTargets.push({
							kind: 'code-line',
							id,
							fenceId,
							startLine: sourceLine,
							endLine: sourceLine,
						});
						node.tagName = 'div';
						node.properties['data-bridge-markdown-target'] = id;
					},
				},
			],
		});
	};

	const tokens = markdownRenderer.parse(markdownText);
	annotateMarkdownBlockTokens({ renderer: markdownRenderer, tokens, targets: annotationTargets });
	const htmlCandidate = await markdownRenderer.renderer.renderAsync(
		tokens,
		markdownRenderer.options,
		{},
	);
	const orderedTargets = annotationTargets.toSorted(
		(left, right): number => left.startLine - right.startLine,
	);
	const sourceLineCount = markdownText.split(/\r\n|\r|\n/u).length;
	if (orderedTargets.some((target): boolean => target.endLine > sourceLineCount))
		throw new Error('Markdown target exceeds source');
	return { htmlCandidate, mermaidDiagrams, annotationTargets: orderedTargets };
}

function normalizedFenceLanguage(info: string): string {
	return info.trim().split(/\s+/u)[0]?.toLowerCase() ?? '';
}

function supportedMarkdownLanguage(
	highlighter: HighlighterCore,
	language: string | undefined,
): string {
	if (language === undefined || language.length === 0) {
		return 'text';
	}
	if (highlighter.getLoadedLanguages().includes(language)) {
		return language;
	}
	return 'text';
}

function byteLength(value: string): number {
	return new TextEncoder().encode(value).byteLength;
}
