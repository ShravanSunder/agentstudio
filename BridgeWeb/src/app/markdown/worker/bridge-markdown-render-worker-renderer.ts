import { fromAsyncCodeToHtml } from '@shikijs/markdown-exit';
import { createMarkdownExit } from 'markdown-exit';
import { createHighlighterCore, type CodeToHastOptions, type HighlighterCore } from 'shiki/core';
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

import {
	bridgeMarkdownRenderWorkerSuccessResponseSchema,
	identityFromMarkdownRenderWorkerRequest,
	type BridgeMarkdownMermaidDiagram,
	type BridgeMarkdownRenderWorkerRequest,
	type BridgeMarkdownRenderWorkerSuccessResponse,
} from './bridge-markdown-render-worker-rpc.js';

interface BridgeMarkdownRenderOutput {
	readonly htmlCandidate: string;
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
	markdownRenderer.use(
		fromAsyncCodeToHtml(codeToHtmlWithStaticHighlighter, {
			themes: {
				dark: 'github-dark',
				light: 'github-dark',
			},
		}),
	);

	const mermaidDiagrams: BridgeMarkdownMermaidDiagram[] = [];
	const renderFence = markdownRenderer.renderer.rules.fence;
	markdownRenderer.renderer.rules.fence = async (tokens, index, options, environment, self) => {
		const token = tokens[index];
		if (token === undefined || normalizedFenceLanguage(token.info) !== 'mermaid') {
			const renderedFence =
				renderFence === undefined
					? self.renderToken(tokens, index, options, environment)
					: await renderFence(tokens, index, options, environment, self);
			return renderedFence;
		}
		const id = `mermaid-${mermaidDiagrams.length.toString()}`;
		mermaidDiagrams.push({ id, source: token.content });
		return `<div class="bridge-markdown-mermaid" data-bridge-mermaid-id="${id}"></div>`;
	};

	const tokens = markdownRenderer.parse(markdownText);
	const htmlCandidate = await markdownRenderer.renderer.renderAsync(
		tokens,
		markdownRenderer.options,
		{},
	);
	return { htmlCandidate, mermaidDiagrams };
}

function normalizedFenceLanguage(info: string): string {
	return info.trim().split(/\s+/u)[0]?.toLowerCase() ?? '';
}

async function codeToHtmlWithStaticHighlighter(
	code: string,
	options: CodeToHastOptions,
): Promise<string> {
	const highlighter = await bridgeMarkdownHighlighterPromise;
	return highlighter.codeToHtml(code, {
		...options,
		lang: supportedMarkdownLanguage(highlighter, options.lang),
		theme: 'github-dark',
	});
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
