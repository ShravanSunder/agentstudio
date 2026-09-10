import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';
import { page, userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import './bridge-app.css';
import { Switch, SwitchIndicator } from '../components/ui/switch.js';
import { BridgeViewerViewSettingsMenu } from './bridge-viewer-view-settings-menu.js';

describe('BridgeViewerViewSettingsMenu Browser Mode', () => {
	test('keeps settings and reset reachable in a short viewport', async () => {
		const originalSize = { width: window.innerWidth, height: window.innerHeight };
		await page.viewport(320, 120);
		const defaults = {
			changeBackgrounds: true,
			changeIndicators: 'bars' as const,
			diffLayout: 'split' as const,
			lineNumbers: true,
			wordWrap: true,
		};
		const onChange = vi.fn();
		const rendered = await render(
			<BridgeViewerViewSettingsMenu
				defaultSettings={defaults}
				settings={{ ...defaults, wordWrap: false }}
				onChange={onChange}
				onOpenChange={() => undefined}
				open
				surface="review"
			/>,
		);
		try {
			await settleMenuGeometry('[data-testid="bridge-review-view-settings-content"]');
			const popup = requireHTMLElement(
				document.querySelector('[data-testid="bridge-review-view-settings-content"]'),
			);
			expect(popup.getBoundingClientRect().bottom).toBeLessThanOrEqual(window.innerHeight);
			expect(popup.getBoundingClientRect().left).toBeGreaterThanOrEqual(0);
			expect(popup.getBoundingClientRect().right).toBeLessThanOrEqual(window.innerWidth);
			expect(popup.scrollHeight).toBeGreaterThan(popup.clientHeight);
			await act(async (): Promise<void> => {
				await rendered.getByRole('button', { name: 'Reset defaults' }).click();
			});
			expect(onChange).toHaveBeenCalledWith(defaults);
		} finally {
			await act(async (): Promise<void> => {
				await rendered.unmount();
			});
			await page.viewport(originalSize.width, originalSize.height);
		}
	});
	test('Files exposes only its two labelled switches through the shared popover', async () => {
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
		const popup = requireHTMLElement(
			document.querySelector('[data-testid="bridge-file-view-settings-content"]'),
		);
		expect(popup.getAttribute('data-scrollable')).toBe('true');
		expect(getComputedStyle(popup).overflowY).toBe('auto');
		expect(getComputedStyle(popup).maxHeight).not.toBe('none');

		// Act
		const appearanceSwitches = findControls('Appearance', 'switch');

		// Assert
		expect(appearanceSwitches.map(accessibleControlLabel)).toEqual(['Line numbers', 'Word wrap']);
		expect(appearanceSwitches.map(checkedState)).toEqual(['true', 'false']);
		expect(appearanceSwitches.map(switchThumbIsVisible)).toEqual([true, true]);
		expect(appearanceSwitches.map(switchThumbOffset)).toEqual([13, 1]);
		const switchInputIds = switchHiddenInputIds('Appearance');
		expect(labelTargets('Appearance')).toEqual(switchInputIds);
		expect(new Set(switchInputIds).size).toBe(2);
		expect(fieldIconSizes('Appearance')).toEqual([
			{ height: 14, width: 14 },
			{ height: 14, width: 14 },
		]);
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
		expect(document.querySelector('[role="menu"]')).toBeNull();

		// Act
		appearanceSwitches[1]?.focus();
		await userEvent.keyboard(' ');

		// Assert
		expect(onChange).toHaveBeenCalledExactlyOnceWith({ lineNumbers: true, wordWrap: true });
	});

	test('Review exposes only two switches and aligned layout choices, with reset', async () => {
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
		const appearanceSwitches = findControls('Appearance', 'switch');
		const layoutChoices = findControls('Layout', 'button');

		// Assert
		expect(appearanceSwitches.map(accessibleControlLabel)).toEqual(['Line numbers', 'Word wrap']);
		expect(appearanceSwitches.map(checkedState)).toEqual(['true', 'true']);
		expect(layoutChoices.map(accessibleControlLabel)).toEqual(['Split', 'Unified']);
		expect(layoutChoices.map(pressedState)).toEqual(['false', 'true']);
		expect(layoutChoices.every(controlHasMeaningfulIcon)).toBe(true);
		expect(horizontalFieldRows()).toBe(true);
		expect(document.body.textContent).not.toContain('Change backgrounds');
		expect(document.body.textContent).not.toContain('Change indicators');
		const settingRows = [...document.querySelectorAll<HTMLElement>('[data-orientation="setting"]')];
		const labelBounds = settingRows.map((row) =>
			requireHTMLElement(row.querySelector('[data-slot="field-label"]')).getBoundingClientRect(),
		);
		expect(new Set(labelBounds.map((bounds) => Math.round(bounds.left))).size).toBe(1);
		const controlBounds = settingRows.map((row) =>
			requireHTMLElement(
				row.querySelector('[data-slot="switch"], [data-slot="toggle-group"]'),
			).getBoundingClientRect(),
		);
		expect(new Set(controlBounds.map((bounds) => Math.round(bounds.right))).size).toBe(1);
		for (const [index, label] of labelBounds.entries()) {
			expect((controlBounds[index]?.left ?? 0) - label.right).toBeGreaterThanOrEqual(12);
		}
		const popupBounds = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-view-settings-content"]'),
		).getBoundingClientRect();
		for (const control of controlBounds) {
			expect(control.right).toBeLessThanOrEqual(popupBounds.right - 8);
		}
		const settingsGrid = document.querySelector(
			'[data-slot="field-group"][data-layout="settings"]',
		);
		expect(settingsGrid).not.toBeNull();
		expect(
			settingsGrid?.querySelector('[data-testid="bridge-review-view-settings-reset"]'),
		).toBeNull();
		for (const control of appearanceSwitches)
			expect(control.getBoundingClientRect().width).toBe(28);
		for (const row of settingRows) {
			const label = requireHTMLElement(row.querySelector('[data-slot="field-label"]'));
			expect(getComputedStyle(label).fontWeight).toBe('400');
			expect(getComputedStyle(label).fontSize).toBe('12px');
			expect(label.getBoundingClientRect().height).toBe(16);
			expect(row.getBoundingClientRect().height).toBe(28);
		}
		expect(elementSize('[data-testid="bridge-review-view-settings-trigger"]')).toEqual({
			height: 24,
			width: 24,
		});
		expect(elementSize('[data-testid="bridge-review-view-settings-content"]')).toMatchObject({
			width: 288,
		});
		// Act
		await act(async (): Promise<void> => {
			requireHTMLElement(
				document.querySelector('[data-testid="bridge-review-view-settings-reset"]'),
			).click();
		});

		// Assert
		expect(onChange).toHaveBeenCalledExactlyOnceWith(defaults);
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

	test('shared switch recipes preserve semantic states, focus, and passive indicator parity', async () => {
		const rendered = await render(
			<div>
				<span className="bg-primary/15" data-testid="switch-selected-fill" />
				<Switch aria-label="Enabled setting" checked />
				<Switch aria-label="Off setting" checked={false} />
				<Switch aria-label="Disabled setting" checked disabled />
				<SwitchIndicator checked />
				<SwitchIndicator checked={false} />
			</div>,
		);
		const checkedSwitch = rendered.getByRole('switch', { name: 'Enabled setting' }).element();
		const uncheckedSwitch = rendered.getByRole('switch', { name: 'Off setting' }).element();
		const disabledSwitch = rendered.getByRole('switch', { name: 'Disabled setting' }).element();
		const indicators = [
			...document.querySelectorAll<HTMLElement>('[data-slot="switch-indicator"]'),
		];
		expect(checkedSwitch).toHaveAttribute('aria-checked', 'true');
		expect(uncheckedSwitch).toHaveAttribute('aria-checked', 'false');
		expect(getComputedStyle(checkedSwitch).backgroundColor).toBe(
			getComputedStyle(rendered.getByTestId('switch-selected-fill').element()).backgroundColor,
		);
		expect(getComputedStyle(checkedSwitch).borderColor).toBe('rgba(0, 0, 0, 0)');
		expect(
			getComputedStyle(
				requireHTMLElement(checkedSwitch.querySelector('[data-slot="switch-thumb"]')),
			).backgroundColor,
		).toBe('rgb(137, 180, 250)');
		expect(getComputedStyle(uncheckedSwitch).backgroundColor).toBe('rgb(110, 119, 135)');
		expect(
			getComputedStyle(
				requireHTMLElement(uncheckedSwitch.querySelector('[data-slot="switch-thumb"]')),
			).backgroundColor,
		).toBe('rgb(234, 234, 234)');
		checkedSwitch.focus();
		await userEvent.keyboard('{Tab}');
		expect(uncheckedSwitch).toHaveFocus();
		expect(getComputedStyle(uncheckedSwitch).boxShadow).toContain('0px 0px 0px 2px');
		expect(disabledSwitch).toHaveAttribute('data-disabled');
		expect(getComputedStyle(disabledSwitch).pointerEvents).toBe('none');
		expect(getComputedStyle(disabledSwitch).opacity).toBe('1');
		expect(getComputedStyle(disabledSwitch).backgroundColor).toBe('rgb(54, 54, 54)');
		expect(getComputedStyle(disabledSwitch).borderColor).toBe('rgb(110, 119, 135)');
		expect(
			getComputedStyle(
				requireHTMLElement(disabledSwitch.querySelector('[data-slot="switch-thumb"]')),
			).backgroundColor,
		).toBe('rgb(155, 161, 173)');
		expect(indicators.map((indicator) => elementBounds(indicator))).toEqual([
			{ height: 16, width: 28 },
			{ height: 16, width: 28 },
		]);
		expect(indicators.map(switchThumbOffset)).toEqual([13, 1]);
		expect(indicators.map((indicator) => getComputedStyle(indicator).backgroundColor)).toEqual([
			getComputedStyle(checkedSwitch).backgroundColor,
			getComputedStyle(uncheckedSwitch).backgroundColor,
		]);
		expect(
			indicators.map(
				(indicator) =>
					getComputedStyle(
						requireHTMLElement(indicator.querySelector('[data-slot="switch-thumb"]')),
					).backgroundColor,
			),
		).toEqual([
			getComputedStyle(
				requireHTMLElement(checkedSwitch.querySelector('[data-slot="switch-thumb"]')),
			).backgroundColor,
			getComputedStyle(
				requireHTMLElement(uncheckedSwitch.querySelector('[data-slot="switch-thumb"]')),
			).backgroundColor,
		]);
	});
});

function findControls(groupLabel: string, role: string): HTMLElement[] {
	const group = document.querySelector(`section[aria-label="${groupLabel}"]`);
	expect(group).not.toBeNull();
	const selector = role === 'button' ? 'button' : `[role="${role}"]`;
	return [...(group?.querySelectorAll(selector) ?? [])].map(
		(element: Element): HTMLElement => requireHTMLElement(element),
	);
}

function labelTargets(groupLabel: string): (string | null)[] {
	const group = document.querySelector(`section[aria-label="${groupLabel}"]`);
	expect(group).not.toBeNull();
	return [...(group?.querySelectorAll('label') ?? [])].map((label): string | null =>
		label.getAttribute('for'),
	);
}

function switchHiddenInputIds(groupLabel: string): string[] {
	const group = document.querySelector(`section[aria-label="${groupLabel}"]`);
	expect(group).not.toBeNull();
	return [...(group?.querySelectorAll<HTMLInputElement>('input[type="checkbox"]') ?? [])].map(
		(input): string => input.id,
	);
}

function fieldIconSizes(groupLabel: string): Readonly<{ height: number; width: number }>[] {
	const group = document.querySelector(`section[aria-label="${groupLabel}"]`);
	expect(group).not.toBeNull();
	return [...(group?.querySelectorAll('label svg') ?? [])].map(elementBounds);
}

function horizontalFieldRows(): boolean {
	return [...document.querySelectorAll<HTMLElement>('[data-slot="field"]')].every(
		(field) => field.getAttribute('data-orientation') === 'setting',
	);
}

function accessibleControlLabel(control: HTMLElement): string | null {
	return control.getAttribute('aria-label');
}

function checkedState(row: HTMLElement): string | null {
	return row.getAttribute('aria-checked');
}

function pressedState(control: HTMLElement): string | null {
	return control.getAttribute('aria-pressed');
}

function switchThumbIsVisible(control: HTMLElement): boolean {
	const thumb = requireHTMLElement(control.querySelector('[data-slot="switch-thumb"]'));
	const bounds = thumb.getBoundingClientRect();
	return bounds.width > 0 && bounds.height > 0;
}

function switchThumbOffset(control: HTMLElement): number {
	const thumb = requireHTMLElement(control.querySelector('[data-slot="switch-thumb"]'));
	return Math.round(thumb.getBoundingClientRect().left - control.getBoundingClientRect().left - 1);
}

function controlHasMeaningfulIcon(control: HTMLElement): boolean {
	return control.querySelector('svg[aria-hidden="true"]') !== null;
}

function requireHTMLElement(element: Element | null): HTMLElement {
	if (!(element instanceof HTMLElement)) throw new Error('Expected a real Browser Mode element.');
	return element;
}

function elementSize(selector: string): Readonly<{ height: number; width: number }> {
	return elementBounds(requireHTMLElement(document.querySelector(selector)));
}

function elementBounds(element: Element): Readonly<{ height: number; width: number }> {
	const bounds = element.getBoundingClientRect();
	return { height: bounds.height, width: bounds.width };
}

async function settleMenuGeometry(selector: string): Promise<void> {
	const menu = requireHTMLElement(document.querySelector(selector));
	await Promise.all(
		menu.getAnimations({ subtree: true }).map(async (animation) => animation.finished),
	);
}
