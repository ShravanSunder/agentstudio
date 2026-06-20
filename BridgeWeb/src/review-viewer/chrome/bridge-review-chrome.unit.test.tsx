// @vitest-environment jsdom

import { act } from 'react';
import { createRoot } from 'react-dom/client';
import { afterEach, describe, expect, test } from 'vitest';

import { BridgeReviewButton } from './bridge-review-button.js';
import { BridgeReviewFilterMenu } from './bridge-review-filter-menu.js';
import { BridgeReviewSearchControl } from './bridge-review-search-control.js';

Object.assign(globalThis, { IS_REACT_ACT_ENVIRONMENT: true });

describe('Bridge review chrome controls', () => {
	let mountedRoot: ReturnType<typeof createRoot> | null = null;

	afterEach(() => {
		if (mountedRoot !== null) {
			act((): void => {
				mountedRoot?.unmount();
			});
			mountedRoot = null;
		}
		document.body.replaceChildren();
	});

	test('pressed chrome buttons use quiet fill without a permanent outline', () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		act((): void => {
			mountedRoot?.render(<BridgeReviewButton ariaPressed>All</BridgeReviewButton>);
		});

		const button = requireElement(container.querySelector<HTMLButtonElement>('button'));

		expect(button.getAttribute('aria-pressed')).toBe('true');
		expect(button.className).toContain('bg-[var(--bridge-accent-soft)]');
		expect(button.className).toContain('border-transparent');
		expect(button.className.split(/\s+/)).not.toContain('border-[var(--bridge-border-opaque)]');
		expect(button.className).toContain('hover:border-[var(--bridge-border-opaque)]');
	});

	test('search control avoids native WebKit search input decorations', () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		act((): void => {
			mountedRoot?.render(
				<BridgeReviewSearchControl isActive={false} onOpenSearch={() => undefined} />,
			);
		});

		const button = requireElement(
			container.querySelector<HTMLButtonElement>('[data-testid="bridge-review-search-toggle"]'),
		);

		expect(button.type).toBe('button');
		expect(container.querySelector('input[role="searchbox"]')).toBeNull();
	});

	test('search trigger opens the Pierre tree search row instead of rendering a second input', () => {
		let openRequestCount = 0;
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		act((): void => {
			mountedRoot?.render(
				<BridgeReviewSearchControl
					isActive={false}
					onOpenSearch={(): void => {
						openRequestCount += 1;
					}}
				/>,
			);
		});

		const button = requireElement(
			container.querySelector('[data-testid="bridge-review-search-toggle"]'),
		);

		act((): void => {
			button.dispatchEvent(new MouseEvent('click', { bubbles: true }));
		});
		expect(openRequestCount).toBe(1);
		expect(container.querySelector('input[role="searchbox"]')).toBeNull();
	});

	test('search trigger stays icon-only in the rail toolbar', () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		act((): void => {
			mountedRoot?.render(<BridgeReviewSearchControl isActive onOpenSearch={() => undefined} />);
		});

		const button = requireElement(
			container.querySelector<HTMLButtonElement>('[data-testid="bridge-review-search-toggle"]'),
		);

		expect(button.className).toContain('h-7');
		expect(button.className).toContain('w-7');
		expect(button.className).toContain('bg-[var(--bridge-accent-soft)]');
	});

	test('filter menu trigger uses an icon chevron instead of a text glyph', () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		act((): void => {
			mountedRoot?.render(
				<BridgeReviewFilterMenu
					label="Git status filter"
					onChange={() => undefined}
					options={[
						{ value: 'all', label: 'All statuses', icon: 'All' },
						{ value: 'added', label: 'Added', icon: 'A' },
					]}
					testId="test-filter"
					value="all"
				/>,
			);
		});

		const chevron = requireElement(
			container.querySelector('[data-testid="bridge-review-filter-chevron"]'),
		);
		expect(chevron.textContent).toBe('');
		expect(chevron.tagName.toLowerCase()).toBe('svg');
	});

	test('filter menu trigger uses compact rail label instead of form-control copy', () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		act((): void => {
			mountedRoot?.render(
				<BridgeReviewFilterMenu
					label="Git status filter"
					onChange={() => undefined}
					options={[
						{ value: 'all', label: 'All statuses', selectedLabel: 'All', icon: 'All' },
						{ value: 'added', label: 'Added', icon: 'A' },
					]}
					testId="test-filter"
					value="all"
				/>,
			);
		});
		const triggerButton = requireElement(
			container.querySelector<HTMLButtonElement>('[aria-label="Filter by Git status"]'),
		);
		const triggerGlyph = requireElement(
			container.querySelector('[data-testid="bridge-review-filter-trigger-glyph"]'),
		);

		expect(triggerButton.className).toContain('h-8');
		expect(triggerButton.className).toContain('w-9');
		expect(triggerGlyph.tagName.toLowerCase()).toBe('svg');
		expect(triggerButton.textContent).toContain('All');
		expect(triggerButton.textContent).not.toContain('All statuses');
	});

	test('filter menu renders DiffsHub-style popover structure with badges and checks', () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		act((): void => {
			mountedRoot?.render(
				<BridgeReviewFilterMenu
					label="Git status filter"
					onChange={() => undefined}
					options={[
						{ value: 'all', label: 'All statuses', selectedLabel: 'All', icon: '*' },
						{ value: 'added', label: 'Added', icon: 'A' },
						{ value: 'modified', label: 'Modified', icon: 'M' },
						{ value: 'renamed', label: 'Renamed', icon: 'R' },
						{ value: 'deleted', label: 'Deleted', icon: 'D' },
					]}
					testId="test-filter"
					value="added"
				/>,
			);
		});

		const triggerButton = requireElement(
			container.querySelector<HTMLButtonElement>('[aria-label="Filter by Git status"]'),
		);
		act((): void => {
			triggerButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
		});

		const popover = requireElement(
			document.querySelector('[data-testid="bridge-review-filter-popover"]'),
		);
		const header = requireElement(
			document.querySelector('[data-testid="bridge-review-filter-popover-header"]'),
		);
		const optionBadges = document.querySelectorAll(
			'[data-testid="bridge-review-filter-option-badge"]',
		);
		const checkmarks = document.querySelectorAll(
			'[data-slot="dropdown-menu-checkbox-item-indicator"]',
		);
		const checkboxItems = document.querySelectorAll('[role="menuitemcheckbox"]');
		const clearButton = requireElement(
			document.querySelector<HTMLElement>('[data-testid="bridge-review-filter-clear"]'),
		);

		expect(popover.getAttribute('data-slot')).toBe('dropdown-menu-content');
		expect(popover.className).toContain('w-64');
		expect(popover.className).toContain('rounded-[10px]');
		expect(header.textContent).toContain('Filter by Git status');
		expect(header.textContent).toContain('Option-click');
		expect(optionBadges).toHaveLength(5);
		expect(checkmarks).toHaveLength(5);
		expect(checkboxItems).toHaveLength(5);
		expect(clearButton.getAttribute('data-disabled')).toBeNull();
	});

	test('git status filter can use clear action instead of an all-status menu row', () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		act((): void => {
			mountedRoot?.render(
				<BridgeReviewFilterMenu
					label="Git status filter"
					onChange={() => undefined}
					options={[
						{ value: 'all', label: 'All statuses', selectedLabel: 'All', icon: '*' },
						{ value: 'added', label: 'Added', icon: 'A' },
						{ value: 'modified', label: 'Modified', icon: 'M' },
					]}
					showDefaultOptionInMenu={false}
					testId="test-filter"
					value="all"
				/>,
			);
		});

		const triggerButton = requireElement(
			container.querySelector<HTMLButtonElement>('[aria-label="Filter by Git status"]'),
		);
		act((): void => {
			triggerButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
		});

		const checkboxItems = Array.from(document.querySelectorAll('[role="menuitemcheckbox"]'));
		const clearButton = requireElement(
			document.querySelector<HTMLElement>('[data-testid="bridge-review-filter-clear"]'),
		);

		expect(checkboxItems.map((item: Element): string => item.textContent ?? '')).toEqual([
			'AAdded',
			'MModified',
		]);
		expect(
			checkboxItems.map((item: Element): string | null => item.getAttribute('aria-checked')),
		).toEqual(['true', 'true']);
		expect(clearButton.getAttribute('data-disabled')).not.toBeNull();
	});

	test('filtered trigger keeps the filter glyph and uses only a tiny active indicator', () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		act((): void => {
			mountedRoot?.render(
				<BridgeReviewFilterMenu
					label="Git status filter"
					onChange={() => undefined}
					options={[
						{ value: 'all', label: 'All statuses', selectedLabel: 'All', icon: '*' },
						{ value: 'added', label: 'Added', icon: 'A' },
					]}
					testId="test-filter"
					value="added"
				/>,
			);
		});

		const triggerGlyph = requireElement(
			container.querySelector('[data-testid="bridge-review-filter-trigger-glyph"]'),
		);
		const activeIndicator = requireElement(
			container.querySelector('[data-testid="bridge-review-filter-active-indicator"]'),
		);

		expect(triggerGlyph.tagName.toLowerCase()).toBe('svg');
		expect(activeIndicator.className).toContain('size-1.5');
		expect(
			container.querySelector('[data-testid="bridge-review-filter-selected-badge"]'),
		).toBeNull();
	});

	test('filter menu disables clear action when the all option is selected', () => {
		const container = document.createElement('div');
		document.body.append(container);
		mountedRoot = createRoot(container);

		act((): void => {
			mountedRoot?.render(
				<BridgeReviewFilterMenu
					label="Git status filter"
					onChange={() => undefined}
					options={[
						{ value: 'all', label: 'All statuses', selectedLabel: 'All', icon: '*' },
						{ value: 'added', label: 'Added', icon: 'A' },
					]}
					testId="test-filter"
					value="all"
				/>,
			);
		});

		const triggerButton = requireElement(
			container.querySelector<HTMLButtonElement>('[aria-label="Filter by Git status"]'),
		);
		act((): void => {
			triggerButton.dispatchEvent(new MouseEvent('click', { bubbles: true }));
		});

		const clearButton = requireElement(
			document.querySelector<HTMLElement>('[data-testid="bridge-review-filter-clear"]'),
		);

		expect(clearButton.getAttribute('data-disabled')).not.toBeNull();
	});
});

function requireElement<TElement extends Element>(element: TElement | null): TElement {
	if (element === null) {
		throw new Error('expected element');
	}
	return element;
}
