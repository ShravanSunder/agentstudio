export type BridgeViewerLocalShortcutId = 'filters' | 'search';

export interface BridgeViewerLocalShortcut {
	readonly id: BridgeViewerLocalShortcutId;
	readonly key: 'f';
	readonly modifiers: {
		readonly alt: boolean;
		readonly meta: true;
		readonly shift: boolean;
	};
	readonly keycap: string;
}

export const bridgeViewerSearchShortcut: BridgeViewerLocalShortcut = {
	id: 'search',
	key: 'f',
	modifiers: { alt: false, meta: true, shift: true },
	keycap: '⌘⇧F',
};

export const bridgeViewerFiltersShortcut: BridgeViewerLocalShortcut = {
	id: 'filters',
	key: 'f',
	modifiers: { alt: true, meta: true, shift: false },
	keycap: '⌘⌥F',
};

export function matchesBridgeViewerLocalShortcut(
	event: Pick<KeyboardEvent, 'altKey' | 'ctrlKey' | 'key' | 'metaKey' | 'shiftKey'>,
	shortcut: BridgeViewerLocalShortcut,
): boolean {
	return (
		event.key.toLowerCase() === shortcut.key &&
		event.metaKey === shortcut.modifiers.meta &&
		event.altKey === shortcut.modifiers.alt &&
		event.shiftKey === shortcut.modifiers.shift &&
		!event.ctrlKey
	);
}

export function bridgeViewerShortcutTitle(
	label: string,
	shortcut: BridgeViewerLocalShortcut,
): string {
	return `${label} (${shortcut.keycap})`;
}
