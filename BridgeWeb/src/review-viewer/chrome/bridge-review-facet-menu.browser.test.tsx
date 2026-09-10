import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import '../../app/bridge-app.css';
import type { BridgeViewerFacetMenuOption } from '../../app/bridge-viewer-filter-menu.js';
import type { BridgeFileChangeKind } from '../../foundation/review-package/bridge-review-package.js';
import { BridgeReviewFacetMenu } from './bridge-review-facet-menu.js';

describe('BridgeReviewFacetMenu Browser Mode', () => {
	test('exposes Git and category groups plus independent Binary and Large visibility toggles', async () => {
		// Arrange
		const onFilterChange = vi.fn();

		await render(
			<BridgeReviewFacetMenu
				categoryFilter="test"
				gitStatusFilter="modified"
				gitStatusOptions={gitStatusOptions}
				onFilterChange={onFilterChange}
				onOpenChange={() => undefined}
				open
				showBinary
				showLarge={false}
			/>,
		);

		// Act
		const gitRows = findMenuCheckboxItems('Git status');
		const categoryRows = findMenuCheckboxItems('File category');
		const visibilityRows = findMenuCheckboxItems('Visibility');

		// Assert
		expect(gitRows.map(visibleRowLabel)).toEqual([
			'All',
			'Added',
			'Modified',
			'Renamed',
			'Deleted',
			'Copied',
		]);
		expect(gitRows.map(checkedState)).toEqual([
			'false',
			'false',
			'true',
			'false',
			'false',
			'false',
		]);
		expect(categoryRows.map(visibleRowLabel)).toEqual([
			'All',
			'Source code',
			'Tests',
			'Documentation',
			'Configuration',
			'Test data',
		]);
		for (const row of categoryRows) {
			expect(row.querySelector('[data-testid$="-option-badge"] svg')).not.toBeNull();
		}
		const categoryBadges = categoryRows.map((row) =>
			requireHTMLElement(row.querySelector('[data-testid$="-option-badge"]')),
		);
		const neutralBadge = categoryBadges[0];
		if (neutralBadge === undefined) throw new Error('All category badge missing');
		for (const badge of categoryBadges) {
			expect(getComputedStyle(badge).color).toBe(getComputedStyle(neutralBadge).color);
			expect(getComputedStyle(badge).backgroundColor).toBe(
				getComputedStyle(neutralBadge).backgroundColor,
			);
		}
		expect(
			new Set(
				gitRows.map(
					(row) =>
						getComputedStyle(
							requireHTMLElement(row.querySelector('[data-testid$="-option-badge"]')),
						).color,
				),
			).size,
		).toBe(5);
		const groupLabels = document.querySelectorAll('[data-slot="dropdown-menu-label"]');
		expect(groupLabels).toHaveLength(2);
		for (const heading of groupLabels) {
			expect(heading.querySelector('svg')).not.toBeNull();
			expect(getComputedStyle(heading).fontSize).toBe('11px');
		}
		expect(document.querySelector('[data-slot="dropdown-menu-sub-trigger"]')).toBeNull();
		for (const rows of [gitRows, categoryRows]) {
			const firstLabel = rows[0]?.querySelector('[data-testid$="-option-label"]');
			expect(firstLabel).not.toBeNull();
			for (const row of rows) {
				const label = requireHTMLElement(row.querySelector('[data-testid$="-option-label"]'));
				expect(getComputedStyle(label).fontSize).toBe('11px');
				expect(label.scrollWidth).toBeLessThanOrEqual(label.clientWidth);
				expect(label.getBoundingClientRect().left).toBe(firstLabel?.getBoundingClientRect().left);
				expect(getComputedStyle(row).height).toBe('28px');
			}
		}
		expect(categoryRows.map(checkedState)).toEqual([
			'false',
			'false',
			'true',
			'false',
			'false',
			'false',
		]);
		expect(visibilityRows.map(visibleRowLabel)).toEqual([
			'Include binary files',
			'Include large files',
		]);
		expect(visibilityRows.map(checkedState)).toEqual(['true', 'false']);
		for (const row of visibilityRows) {
			expect(row.querySelector('[data-slot="switch-indicator"]')).not.toBeNull();
			expect(row.querySelector('[role="switch"]')).toBeNull();
			expect(getComputedStyle(row).height).toBe('28px');
		}

		// Act
		await act(async (): Promise<void> => {
			visibilityRows[0]?.click();
			visibilityRows[1]?.click();
		});

		// Assert
		expect(onFilterChange).toHaveBeenNthCalledWith(1, {
			categoryFilter: 'test',
			gitStatusFilter: 'modified',
			showBinary: false,
			showLarge: false,
			surface: 'review',
		});
		expect(onFilterChange).toHaveBeenNthCalledWith(2, {
			categoryFilter: 'test',
			gitStatusFilter: 'modified',
			showBinary: true,
			showLarge: true,
			surface: 'review',
		});
	});

	test('Clear resets both exclusive groups and both visibility toggles', async () => {
		// Arrange
		const onFilterChange = vi.fn();

		await render(
			<BridgeReviewFacetMenu
				categoryFilter="generated"
				gitStatusFilter="added"
				gitStatusOptions={gitStatusOptions}
				onFilterChange={onFilterChange}
				onOpenChange={() => undefined}
				open
				showBinary
				showLarge
			/>,
		);

		// Act
		await act(async (): Promise<void> => {
			requireHTMLElement(
				document.querySelector('[data-testid="bridge-review-facet-clear"]'),
			).click();
		});

		// Assert
		expect(onFilterChange).toHaveBeenCalledExactlyOnceWith({
			categoryFilter: 'all',
			gitStatusFilter: 'all',
			showBinary: false,
			showLarge: false,
			surface: 'review',
		});
	});
});

const gitStatusOptions: readonly BridgeViewerFacetMenuOption<BridgeFileChangeKind | 'all'>[] = [
	{ value: 'all', label: 'All', description: 'Show every Git status' },
	{ value: 'added', label: 'Added', description: 'Show added files' },
	{ value: 'modified', label: 'Modified', description: 'Show modified files' },
	{ value: 'renamed', label: 'Renamed', description: 'Show renamed files' },
	{ value: 'deleted', label: 'Deleted', description: 'Show deleted files' },
	{ value: 'copied', label: 'Copied', description: 'Show copied files' },
];

function findMenuCheckboxItems(groupLabel: string): HTMLElement[] {
	const group = document.querySelector(`[role="group"][aria-label="${groupLabel}"]`);
	expect(group).not.toBeNull();
	return [...(group?.querySelectorAll('[role="menuitemcheckbox"]') ?? [])].map(
		(element: Element): HTMLElement => requireHTMLElement(element),
	);
}

function visibleRowLabel(row: HTMLElement): string {
	return (
		row
			.querySelector('[data-testid$="-option-label"], [data-bridge-filter-row-label]')
			?.textContent?.trim() ?? ''
	);
}

function checkedState(row: HTMLElement): string | null {
	return row.getAttribute('aria-checked');
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) {
		throw new Error('Expected a real Browser Mode element.');
	}
	return element;
}
