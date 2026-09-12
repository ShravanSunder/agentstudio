import type { ReactElement } from 'react';

import type { WorktreeAnnotationRange } from '../../worktree-annotations/worktree-annotation-interaction.js';
import type { BridgeMarkdownTargetLayout } from './use-bridge-markdown-annotation-layout.js';

/** Full-viewer paint stays outside clipped code/table content and never receives input. */
export function BridgeMarkdownRowBackgrounds(props: {
	readonly layout: readonly BridgeMarkdownTargetLayout[];
	readonly selection: WorktreeAnnotationRange | null;
	readonly activeCommentTargets: ReadonlySet<string>;
}): ReactElement {
	const selectedRows =
		props.selection === null
			? []
			: props.layout.filter(
					(row): boolean =>
						props.selection !== null &&
						row.target.startLine <= props.selection.end &&
						row.target.endLine >= props.selection.start,
				);
	const firstRow = selectedRows[0];
	const lastRow = selectedRows.at(-1);
	return (
		<div className="bridge-markdown-row-backgrounds" aria-hidden="true">
			{firstRow === undefined || lastRow === undefined ? null : (
				<div
					className="bridge-markdown-source-selection"
					data-testid="bridge-markdown-source-selection"
					style={{ top: firstRow.top, height: lastRow.top + lastRow.height - firstRow.top }}
				/>
			)}
			{props.layout
				.filter((row): boolean => row.commentHeight > 0)
				.map(
					(row): ReactElement => (
						<div
							key={row.target.id}
							className="bridge-markdown-comment-lane"
							data-testid="bridge-markdown-comment-lane"
							data-active={props.activeCommentTargets.has(row.target.id)}
							style={{ top: row.commentTop, height: row.commentHeight }}
						/>
					),
				)}
		</div>
	);
}
