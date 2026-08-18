import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production CSS.
import '../../app/bridge-app.css';
import { makeBridgeReviewPackage } from '../../foundation/review-package/bridge-review-package-test-support.js';
import type { BridgeReviewPackage } from '../../foundation/review-package/bridge-review-package.js';
import { createBridgeCodeViewHeaderRenderers } from './bridge-code-view-panel-support.js';
import { makeHydratedWorkerPreparedCodeViewFileItem } from './bridge-code-view-test-fixtures.js';

describe('Bridge CodeView file corner', () => {
	test('renders authoritative counts followed by an owned shadcn file-view command', async () => {
		// Arrange
		const baseReviewPackage = makeBridgeReviewPackage();
		const baseItem = baseReviewPackage.itemsById['item-source'];
		if (baseItem === undefined) throw new Error('Missing file-corner fixture item.');
		const item = { ...baseItem, additions: 7, deletions: 4 };
		const reviewPackage: BridgeReviewPackage = {
			...baseReviewPackage,
			itemsById: { ...baseReviewPackage.itemsById, [item.itemId]: item },
		};
		const openFile = vi.fn<(path: string) => void>();
		const headerRenderers = createBridgeCodeViewHeaderRenderers({
			collapsedItemIds: new Set(),
			onHeaderVisibilityChange: (): void => {},
			onOpenFile: openFile,
			onToggleItemCollapse: (): void => {},
			reviewPackage,
		});
		const codeViewItem = makeHydratedWorkerPreparedCodeViewFileItem({
			cacheKey: item.cacheKey,
			contentRoles: ['base', 'head'],
			contents: 'let fileCorner = true\n',
			item,
		});

		const rendered = await render(
			<div className="flex h-10 w-80 items-center bg-[var(--bridge-header-bg)] px-2">
				{headerRenderers.renderHeaderMetadata(codeViewItem)}
			</div>,
		);
		const metadata = requireHTMLElement(
			document.querySelector('[data-testid="bridge-code-view-header-metadata"]'),
		);
		const button = requireHTMLElement(
			document.querySelector('[data-testid="bridge-code-view-open-file-button"]'),
		);

		// Assert
		expect([...metadata.children].map((child): string | null => child.textContent)).toEqual([
			'-4',
			'+7',
			'',
		]);
		expect(metadata.lastElementChild).toBe(button);
		expect(button.getAttribute('data-slot')).toBe('button');
		expect(button.getAttribute('data-bridge-code-view-file-path')).toBe(item.headPath);
		expect(button.querySelector('svg')).not.toBeNull();
		expect(Math.round(button.getBoundingClientRect().width)).toBe(28);
		expect(Math.round(button.getBoundingClientRect().height)).toBe(28);

		// Act
		await rendered.getByRole('button', { name: `Open ${item.headPath} in Files` }).click();

		// Assert
		expect(openFile).toHaveBeenCalledExactlyOnceWith(item.headPath);
	});
});

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected an HTML element.');
	return element;
}
