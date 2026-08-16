import { useEffect, useState, type ReactElement } from 'react';

import { WorktreeAnnotationMarkdown } from './worktree-annotation-markdown.js';
import { useWorktreeAnnotationMarkdownClient } from './worktree-annotation-surface-provider.js';

export interface WorktreeAnnotationMessageBodyProps {
	readonly body: string;
	readonly messageId: string;
	readonly messageRevision: number;
	readonly path: string | null;
	readonly sessionId: string;
	readonly sessionRevision: number;
}

export function WorktreeAnnotationMessageBody(
	props: WorktreeAnnotationMessageBodyProps,
): ReactElement {
	const markdownClient = useWorktreeAnnotationMarkdownClient();
	const [renderedHtml, setRenderedHtml] = useState<string | null>(null);
	useEffect((): (() => void) | void => {
		setRenderedHtml(null);
		if (markdownClient === null) return;
		const abortKey = `annotation:${props.messageId}`;
		let isCurrent = true;
		const task = markdownClient.startRender({
			abortKey,
			contentCacheKey: `${props.messageId}:${props.messageRevision}`,
			contentHash: `annotation-body:${props.messageRevision}:${new TextEncoder().encode(props.body).byteLength}`,
			markdownText: props.body,
			sourceIdentity: {
				fileId: props.messageId,
				fileVersion: props.messageRevision,
				sourceGeneration: props.sessionRevision,
				sourceId: props.sessionId,
				surface: 'file',
			},
			sourcePath: props.path ?? 'annotation.md',
		});
		void task.completed.then((completion): void => {
			if (isCurrent && completion.status === 'success') {
				setRenderedHtml(completion.response.htmlCandidate);
			}
		});
		return (): void => {
			isCurrent = false;
			markdownClient.abort(abortKey);
		};
	}, [
		markdownClient,
		props.body,
		props.messageId,
		props.messageRevision,
		props.path,
		props.sessionId,
		props.sessionRevision,
	]);
	return renderedHtml === null ? (
		<p className="whitespace-pre-wrap text-xs/relaxed text-[var(--bridge-text-primary)]">
			{props.body}
		</p>
	) : (
		<WorktreeAnnotationMarkdown html={renderedHtml} />
	);
}
