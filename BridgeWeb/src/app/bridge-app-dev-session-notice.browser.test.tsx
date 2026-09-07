import { act } from 'react';
import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';
import { page } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Validate the real development shell styling.
import './bridge-app.css';
import { BridgeAppDevSessionNotice } from './bridge-app-dev-session-notice.js';

describe('development session takeover notice', () => {
	test('offers only explicit takeover and explains why controls are absent', async () => {
		// Arrange
		const takeOver = vi.fn();
		const rendered = await render(<BridgeAppDevSessionNotice onTakeOver={takeOver} />);

		// Assert the inactive presentation before taking any action.
		await expect.element(rendered.getByRole('alert')).toBeVisible();
		await expect
			.element(rendered.getByText('This development session is active in another tab.'))
			.toBeVisible();
		expect(rendered.container.querySelectorAll('button')).toHaveLength(1);
		expect(takeOver).not.toHaveBeenCalled();
		const button = rendered.getByRole('button', { name: 'Use this tab' });
		const bounds = button.element().getBoundingClientRect();
		expect(bounds.height).toBeGreaterThanOrEqual(24);
		expect(bounds.width).toBeGreaterThan(60);
		await act(async (): Promise<void> => {
			await page.screenshot({ path: '../../../tmp/bridge-dev-session-inactive.png' });
		});

		// Act / Assert
		await button.click();
		expect(takeOver).toHaveBeenCalledOnce();
	});
});
