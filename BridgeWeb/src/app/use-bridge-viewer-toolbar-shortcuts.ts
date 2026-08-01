import { useEffect } from 'react';

export interface UseBridgeViewerToolbarShortcutsProps {
	readonly isActive: boolean;
	readonly onToggleFilters: () => void;
	readonly onToggleSearch: () => void;
	readonly target?: EventTarget;
}

export function useBridgeViewerToolbarShortcuts(props: UseBridgeViewerToolbarShortcutsProps): void {
	const { isActive, onToggleFilters, onToggleSearch, target: explicitTarget } = props;
	useEffect((): (() => void) => {
		if (!isActive) {
			return (): void => {};
		}
		const target = explicitTarget ?? document;
		const handleKeyDown = (event: Event): void => {
			if (!(event instanceof KeyboardEvent) || !isBridgeViewerToolbarShortcut(event)) {
				return;
			}
			event.preventDefault();
			if (event.shiftKey) {
				onToggleSearch();
				return;
			}
			onToggleFilters();
		};
		target.addEventListener('keydown', handleKeyDown);
		return (): void => target.removeEventListener('keydown', handleKeyDown);
	}, [explicitTarget, isActive, onToggleFilters, onToggleSearch]);
}

function isBridgeViewerToolbarShortcut(event: KeyboardEvent): boolean {
	if (event.key.toLowerCase() !== 'f' || !event.metaKey || event.ctrlKey) {
		return false;
	}
	return event.shiftKey !== event.altKey;
}
