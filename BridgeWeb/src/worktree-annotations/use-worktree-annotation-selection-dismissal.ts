import { useEffect } from 'react';

export function useWorktreeAnnotationSelectionDismissal(props: {
	readonly active: boolean;
	readonly clearSelection: () => void;
}): void {
	const { active, clearSelection } = props;
	useEffect((): (() => void) | undefined => {
		if (!active) return undefined;
		const handlePointerDown = (event: PointerEvent): void => {
			if (eventPathContainsAnnotationInteraction(event.composedPath())) return;
			clearSelection();
		};
		const handleKeyDown = (event: KeyboardEvent): void => {
			if (event.key !== 'Escape' || eventPathContainsTextEditor(event.composedPath())) return;
			clearSelection();
		};
		document.addEventListener('pointerdown', handlePointerDown, true);
		document.addEventListener('keydown', handleKeyDown);
		return (): void => {
			document.removeEventListener('pointerdown', handlePointerDown, true);
			document.removeEventListener('keydown', handleKeyDown);
		};
	}, [active, clearSelection]);
}

function eventPathContainsAnnotationInteraction(path: readonly EventTarget[]): boolean {
	return path.some(
		(target): boolean =>
			target instanceof Element &&
			(target.matches('[data-column-number]') ||
				target.matches('[data-utility-button]') ||
				target.matches('[data-annotation-content]') ||
				target.matches('[data-testid="worktree-annotation-conversation-frame"]')),
	);
}

function eventPathContainsTextEditor(path: readonly EventTarget[]): boolean {
	return path.some(
		(target): boolean =>
			target instanceof HTMLElement &&
			(target.matches('textarea, input') || target.isContentEditable),
	);
}
