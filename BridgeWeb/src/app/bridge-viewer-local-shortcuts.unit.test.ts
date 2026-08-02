import { describe, expect, test } from 'vitest';

import {
	bridgeViewerFiltersShortcut,
	bridgeViewerSearchShortcut,
	bridgeViewerShortcutTitle,
	matchesBridgeViewerLocalShortcut,
} from './bridge-viewer-local-shortcuts.js';

describe('Bridge viewer local shortcuts', () => {
	test('matches Search and Filters from their typed descriptors', () => {
		expect(
			matchesBridgeViewerLocalShortcut(
				keyboardEvent({ shiftKey: true }),
				bridgeViewerSearchShortcut,
			),
		).toBe(true);
		expect(
			matchesBridgeViewerLocalShortcut(
				keyboardEvent({ altKey: true }),
				bridgeViewerFiltersShortcut,
			),
		).toBe(true);
	});

	test('leaves plain Command-F and Command-Option-Shift-F unclaimed', () => {
		const plainFind = keyboardEvent({});
		const alternateChord = keyboardEvent({ altKey: true, shiftKey: true });

		expect(matchesBridgeViewerLocalShortcut(plainFind, bridgeViewerSearchShortcut)).toBe(false);
		expect(matchesBridgeViewerLocalShortcut(plainFind, bridgeViewerFiltersShortcut)).toBe(false);
		expect(matchesBridgeViewerLocalShortcut(alternateChord, bridgeViewerSearchShortcut)).toBe(
			false,
		);
		expect(matchesBridgeViewerLocalShortcut(alternateChord, bridgeViewerFiltersShortcut)).toBe(
			false,
		);
	});

	test('derives keycap presentation from the same descriptors', () => {
		expect(bridgeViewerShortcutTitle('Search files', bridgeViewerSearchShortcut)).toBe(
			'Search files (⌘⇧F)',
		);
		expect(bridgeViewerShortcutTitle('Filter files', bridgeViewerFiltersShortcut)).toBe(
			'Filter files (⌘⌥F)',
		);
	});
});

function keyboardEvent(modifiers: {
	readonly altKey?: boolean;
	readonly shiftKey?: boolean;
}): Pick<KeyboardEvent, 'altKey' | 'ctrlKey' | 'key' | 'metaKey' | 'shiftKey'> {
	return {
		altKey: modifiers.altKey ?? false,
		ctrlKey: false,
		key: 'f',
		metaKey: true,
		shiftKey: modifiers.shiftKey ?? false,
	};
}
