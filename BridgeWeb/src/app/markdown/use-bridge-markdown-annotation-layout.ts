import { useLayoutEffect, useState, type RefObject } from 'react';

import type { BridgeMarkdownSourceTarget } from './bridge-markdown-source-target.js';

export interface BridgeMarkdownTargetLayout {
	readonly target: BridgeMarkdownSourceTarget;
	readonly top: number;
	readonly height: number;
	readonly firstLineCenter: number;
	readonly commentTop: number;
	readonly commentHeight: number;
	readonly element: HTMLElement;
	readonly host: HTMLElement;
}

export function useBridgeMarkdownAnnotationLayout(props: {
	readonly articleRef: RefObject<HTMLElement | null>;
	readonly targets: readonly BridgeMarkdownSourceTarget[];
}): readonly BridgeMarkdownTargetLayout[] {
	const [layout, setLayout] = useState<readonly BridgeMarkdownTargetLayout[]>([]);
	useLayoutEffect((): (() => void) | undefined => {
		const article = props.articleRef.current;
		if (article === null) return undefined;
		const entries = props.targets.flatMap((target) => {
			const elements = article.querySelectorAll<HTMLElement>(
				`[data-bridge-markdown-target="${CSS.escape(target.id)}"]`,
			);
			const element = elements[0];
			if (elements.length !== 1 || element === undefined) return [];
			const host = document.createElement('div');
			host.className = 'bridge-markdown-annotation-host';
			let mount: HTMLElement = host;
			if (target.kind === 'table-row') {
				if (!(element instanceof HTMLTableRowElement)) return [];
				const row = document.createElement('tr');
				row.className = 'bridge-markdown-annotation-row';
				const cell = document.createElement('td');
				cell.colSpan = element.cells.length;
				cell.append(host);
				row.append(cell);
				mount = row;
			}
			element.after(mount);
			return [{ target, element, host, mount }];
		});
		let frame = 0;
		const measure = (): void => {
			cancelAnimationFrame(frame);
			frame = requestAnimationFrame((): void => {
				const articleTop = article.getBoundingClientRect().top;
				const next = entries.map((entry): BridgeMarkdownTargetLayout => {
					const bounds = entry.element.getBoundingClientRect();
					const commentBounds = entry.host.getBoundingClientRect();
					const firstLine =
						entry.element instanceof HTMLTableRowElement
							? (entry.element.cells[0] ?? entry.element)
							: entry.element;
					const style = getComputedStyle(firstLine);
					const lineHeight = Number.parseFloat(style.lineHeight);
					return {
						...entry,
						top: bounds.top - articleTop,
						height: bounds.height,
						commentTop: commentBounds.top - articleTop,
						commentHeight: commentBounds.height,
						firstLineCenter:
							entry.target.kind === 'diagram'
								? 10
								: Number.parseFloat(style.paddingTop) +
									Number.parseFloat(style.borderTopWidth) +
									(Number.isFinite(lineHeight)
										? lineHeight
										: Number.parseFloat(style.fontSize) * 1.2) /
										2,
					};
				});
				setLayout((previous): readonly BridgeMarkdownTargetLayout[] =>
					previous.length === next.length &&
					previous.every(
						(row, index): boolean =>
							row.host === next[index]?.host &&
							row.top === next[index]?.top &&
							row.height === next[index]?.height &&
							row.commentTop === next[index]?.commentTop &&
							row.commentHeight === next[index]?.commentHeight &&
							row.firstLineCenter === next[index]?.firstLineCenter,
					)
						? previous
						: next,
				);
			});
		};
		const observer = new ResizeObserver(measure);
		observer.observe(article);
		for (const entry of entries) {
			observer.observe(entry.element);
			observer.observe(entry.host);
		}
		measure();
		return (): void => {
			cancelAnimationFrame(frame);
			observer.disconnect();
			for (const entry of entries) entry.mount.remove();
		};
	}, [props.articleRef, props.targets]);
	return layout;
}
