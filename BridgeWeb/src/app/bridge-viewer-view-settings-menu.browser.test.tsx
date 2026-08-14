import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import './bridge-app.css';
import { BridgeViewerViewSettingsMenu } from './bridge-viewer-view-settings-menu.js';

describe('BridgeViewerViewSettingsMenu Browser Mode', () => {
	test('Files exposes only its two appearance toggles through the shared dropdown', async () => {
		// Arrange
		const onChange = vi.fn();
		await render(
			<BridgeViewerViewSettingsMenu
				defaultSettings={{ lineNumbers: true, wordWrap: true }}
				onChange={onChange}
				onOpenChange={() => undefined}
				open
				settings={{ lineNumbers: true, wordWrap: false }}
				surface="file"
			/>,
		);
		await settleMenuGeometry('[data-testid="bridge-file-view-settings-content"]');

		// Act
		const appearanceRows = findMenuItems('Appearance', 'menuitemcheckbox');

		// Assert
		expect(appearanceRows.map(visibleRowLabel)).toEqual(['Line numbers', 'Word wrap']);
		expect(appearanceRows.map(checkedState)).toEqual(['true', 'false']);
		expect(document.body.textContent).not.toContain('Change backgrounds');
		expect(document.body.textContent).not.toContain('Diff layout');
		expect(document.body.textContent).not.toContain('Change indicators');
		expect(elementSize('[data-testid="bridge-file-view-settings-trigger"]')).toEqual({
			height: 24,
			width: 24,
		});
		expect(elementSize('[data-testid="bridge-file-view-settings-content"]')).toMatchObject({
			width: 256,
		});
		expect(appearanceRows.map((row): number => row.getBoundingClientRect().height)).toEqual([
			32, 32,
		]);

		// Act
		await act(async (): Promise<void> => appearanceRows[1]?.click());

		// Assert
		expect(onChange).toHaveBeenCalledExactlyOnceWith({ lineNumbers: true, wordWrap: true });
	});

	test('Review exposes appearance toggles, layout and indicator choices, and reset', async () => {
		// Arrange
		const onChange = vi.fn();
		const defaults = {
			changeBackgrounds: true,
			changeIndicators: 'bars' as const,
			diffLayout: 'split' as const,
			lineNumbers: true,
			wordWrap: true,
		};
		await render(
			<BridgeViewerViewSettingsMenu
				defaultSettings={defaults}
				onChange={onChange}
				onOpenChange={() => undefined}
				open
				settings={{
					...defaults,
					changeBackgrounds: false,
					changeIndicators: 'symbols',
					diffLayout: 'unified',
				}}
				surface="review"
			/>,
		);
		await settleMenuGeometry('[data-testid="bridge-review-view-settings-content"]');

		// Act
		const appearanceRows = findMenuItems('Appearance', 'menuitemcheckbox');
		const layoutRows = findMenuItems('Diff layout', 'menuitemradio');
		const indicatorRows = findMenuItems('Change indicators', 'menuitemradio');

		// Assert
		expect(appearanceRows.map(visibleRowLabel)).toEqual([
			'Line numbers',
			'Word wrap',
			'Change backgrounds',
		]);
		expect(appearanceRows.map(checkedState)).toEqual(['true', 'true', 'false']);
		expect(layoutRows.map(visibleRowLabel)).toEqual(['Split', 'Unified']);
		expect(layoutRows.map(checkedState)).toEqual(['false', 'true']);
		expect(indicatorRows.map(visibleRowLabel)).toEqual(['Bars', 'Symbols', 'None']);
		expect(indicatorRows.map(checkedState)).toEqual(['false', 'true', 'false']);
		expect(elementSize('[data-testid="bridge-review-view-settings-trigger"]')).toEqual({
			height: 24,
			width: 24,
		});
		expect(elementSize('[data-testid="bridge-review-view-settings-content"]')).toMatchObject({
			width: 256,
		});
		expect(appearanceRows.map((row): number => row.getBoundingClientRect().height)).toEqual([
			32, 32, 32,
		]);

		// Act
		await act(async (): Promise<void> => indicatorRows[2]?.click());
		await act(async (): Promise<void> => {
			requireHTMLElement(
				document.querySelector('[data-testid="bridge-review-view-settings-reset"]'),
			).click();
		});

		// Assert
		expect(onChange).toHaveBeenNthCalledWith(1, {
			...defaults,
			changeBackgrounds: false,
			changeIndicators: 'none',
			diffLayout: 'unified',
		});
		expect(onChange).toHaveBeenNthCalledWith(2, defaults);
	});

	test('requests closure when an open menu becomes disabled', async () => {
		const onOpenChange = vi.fn();
		const settings = { lineNumbers: true, wordWrap: true };
		const rendered = await render(
			<BridgeViewerViewSettingsMenu
				defaultSettings={settings}
				onChange={vi.fn()}
				onOpenChange={onOpenChange}
				open
				settings={settings}
				surface="file"
			/>,
		);

		await rendered.rerender(
			<BridgeViewerViewSettingsMenu
				defaultSettings={settings}
				disabled
				onChange={vi.fn()}
				onOpenChange={onOpenChange}
				open
				settings={settings}
				surface="file"
			/>,
		);

		await expect.poll(() => onOpenChange.mock.calls).toContainEqual([false]);
	});
});

function findMenuItems(groupLabel: string, role: string): HTMLElement[] {
	const group = document.querySelector(`section[aria-label="${groupLabel}"]`);
	expect(group).not.toBeNull();
	return [...(group?.querySelectorAll(`[role="${role}"]`) ?? [])].map(
		(element: Element): HTMLElement => requireHTMLElement(element),
	);
}

function visibleRowLabel(row: HTMLElement): string {
	return row.querySelector('[data-bridge-view-settings-row-label]')?.textContent?.trim() ?? '';
}

function checkedState(row: HTMLElement): string | null {
	return row.getAttribute('aria-checked');
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected a real Browser Mode element.');
	return element;
}

function elementSize(selector: string): Readonly<{ height: number; width: number }> {
	const bounds = requireHTMLElement(document.querySelector(selector)).getBoundingClientRect();
	return { height: bounds.height, width: bounds.width };
}

async function settleMenuGeometry(selector: string): Promise<void> {
	const menu = requireHTMLElement(document.querySelector(selector));
	await Promise.all(
		menu.getAnimations({ subtree: true }).map(async (animation) => animation.finished),
	);
}
