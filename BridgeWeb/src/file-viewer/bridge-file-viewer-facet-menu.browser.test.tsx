import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../app/bridge-app.css';
import type { BridgeFileViewerFilterMode } from './bridge-file-viewer-contracts.js';
import { BridgeFileViewerFacetMenu } from './bridge-file-viewer-facet-menu.js';

describe('BridgeFileViewerFacetMenu Browser Mode', () => {
	test('exposes only the accepted exclusive category labels', async () => {
		// Arrange
		const filterModeChanges = vi.fn<(filterMode: BridgeFileViewerFilterMode) => void>();

		await render(
			<BridgeFileViewerFacetMenu
				filterMode="source"
				onFilterModeChange={filterModeChanges}
				onOpenChange={() => undefined}
				open
			/>,
		);

		// Act
		const categoryRows = findMenuCheckboxItems('File category');

		// Assert
		expect(categoryRows.map(visibleRowLabel)).toEqual([
			'All',
			'Source code',
			'Tests',
			'Documentation',
			'Configuration',
			'Generated',
			'Dependencies and build output',
			'Fixtures',
			'Other',
		]);
		expect(
			categoryRows.map((row: HTMLElement): string | null => row.getAttribute('aria-checked')),
		).toEqual(['false', 'true', 'false', 'false', 'false', 'false', 'false', 'false', 'false']);
		expect(document.body.textContent).not.toContain('Binary');
		expect(document.body.textContent).not.toContain('Large');
		expect(document.body.textContent).not.toContain('Git status');
	});
});

function findMenuCheckboxItems(groupLabel: string): HTMLElement[] {
	const group = document.querySelector(`section[aria-label="${groupLabel}"]`);
	expect(group).not.toBeNull();
	return [...(group?.querySelectorAll('[role="menuitemcheckbox"]') ?? [])].map(
		(element: Element): HTMLElement => requireHTMLElement(element),
	);
}

function visibleRowLabel(row: HTMLElement): string {
	return row.querySelector('[data-testid$="-option-label"]')?.textContent?.trim() ?? '';
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) {
		throw new Error('Expected a real Browser Mode element.');
	}
	return element;
}
