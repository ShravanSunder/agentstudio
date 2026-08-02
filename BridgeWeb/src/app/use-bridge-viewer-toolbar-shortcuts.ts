import { useEffect } from 'react';

import {
	bridgeViewerFiltersShortcut,
	bridgeViewerSearchShortcut,
	matchesBridgeViewerLocalShortcut,
} from './bridge-viewer-local-shortcuts.js';

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
			if (!(event instanceof KeyboardEvent)) {
				return;
			}
			if (matchesBridgeViewerLocalShortcut(event, bridgeViewerSearchShortcut)) {
				event.preventDefault();
				onToggleSearch();
				return;
			}
			if (matchesBridgeViewerLocalShortcut(event, bridgeViewerFiltersShortcut)) {
				event.preventDefault();
				onToggleFilters();
			}
		};
		target.addEventListener('keydown', handleKeyDown);
		return (): void => target.removeEventListener('keydown', handleKeyDown);
	}, [explicitTarget, isActive, onToggleFilters, onToggleSearch]);
}
