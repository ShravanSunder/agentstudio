import type { BridgeMarkdownSourceTarget } from '../bridge-markdown-source-target.js';
import type {
	BridgeMarkdownRenderer,
	BridgeMarkdownTokens,
} from './bridge-markdown-render-worker-renderer.js';

export function annotateMarkdownBlockTokens(props: {
	readonly renderer: BridgeMarkdownRenderer;
	readonly tokens: BridgeMarkdownTokens;
	readonly targets: BridgeMarkdownSourceTarget[];
}): void {
	let listDepth = 0;
	for (const [index, token] of props.tokens.entries()) {
		if (token.type === 'list_item_close') listDepth -= 1;
		if (token.type === 'paragraph_open' || token.type === 'paragraph_close') token.hidden = false;
		const block =
			token.type === 'heading_open'
				? 'heading'
				: token.type === 'paragraph_open'
					? listDepth > 0
						? 'list-item'
						: 'paragraph'
					: null;
		if (token.map !== null && (block !== null || token.type === 'tr_open')) {
			const id = `block-${token.map[0] + 1}`;
			const range = { id, startLine: token.map[0] + 1, endLine: token.map[1] };
			props.targets.push(
				block === null ? { ...range, kind: 'table-row' } : { ...range, kind: 'prose', block },
			);
			token.attrSet('data-bridge-markdown-target', id);
		}
		if (block === 'list-item') {
			token.attrJoin('class', 'bridge-markdown-list-text');
			const firstText = props.tokens[index + 1]?.children?.[0];
			if (
				props.tokens[index - 1]?.type === 'list_item_open' &&
				firstText?.type === 'text' &&
				/^\[[ xX]\] /u.test(firstText.content)
			) {
				token.attrSet(
					'data-bridge-markdown-task',
					firstText.content[1]?.toLowerCase() === 'x' ? 'checked' : 'unchecked',
				);
				firstText.content = firstText.content.slice(4);
				props.tokens[index - 1]?.attrJoin('class', 'bridge-markdown-task-item');
			}
		}
		if (token.type === 'list_item_open') listDepth += 1;
	}
	props.renderer.renderer.rules['paragraph_open'] = (
		tokens,
		index,
		options,
		environment,
		renderer,
	): string => {
		const task = tokens[index]?.attrGet('data-bridge-markdown-task');
		const opening = renderer.renderToken(tokens, index, options, environment);
		return task === null || task === undefined
			? opening
			: `${opening}<span class="bridge-markdown-task-check" role="img" aria-label="${task === 'checked' ? 'Completed task' : 'Incomplete task'}">${task === 'checked' ? '☑' : '☐'}</span> `;
	};
	props.renderer.renderer.rules['table_open'] = (): string =>
		'<div class="bridge-markdown-table-scroll"><table>';
	props.renderer.renderer.rules['table_close'] = (): string => '</table></div>';
	props.renderer.renderer.rules.code_block = (tokens, index): string => {
		const token = tokens[index];
		if (token === undefined || token.map === null)
			throw new Error('Missing Markdown code block source map');
		const id = `code-block-${token.map[0] + 1}`;
		props.targets.push({
			kind: 'code-block',
			id,
			startLine: token.map[0] + 1,
			endLine: token.map[1],
		});
		return `<div class="bridge-markdown-code-block" data-bridge-markdown-target="${id}"><pre><code>${props.renderer.utils.escapeHtml(token.content)}</code></pre></div>`;
	};
}
