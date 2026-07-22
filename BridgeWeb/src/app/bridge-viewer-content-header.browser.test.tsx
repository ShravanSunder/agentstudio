import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import './bridge-app.css';
import { BridgeReviewProjectionMenu } from '../review-viewer/chrome/bridge-review-projection-menu.js';
import {
	BridgeViewerContentHeader,
	BridgeViewerContextSwitcher,
} from './bridge-viewer-content-header.js';

describe('BridgeViewerContentHeader Browser Mode', () => {
	test('presents optional updating status accessibly without moving title or controls', async () => {
		// Arrange
		const rendered = await render(
			<BridgeViewerContentHeader
				controls={<button data-testid="header-proof-control">Control</button>}
				eyebrow="Files"
				statusText="Updating files…"
				title="src/app.ts"
			/>,
		);
		const topbar = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-content-topbar"]'),
		);
		const title = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-content-title"]'),
		);
		const controls = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-content-topbar-controls"]'),
		);
		const status = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-content-status"]'),
		);
		const topbarBoxWithStatus = topbar.getBoundingClientRect();
		const titleBoxWithStatus = title.getBoundingClientRect();
		const controlsBoxWithStatus = controls.getBoundingClientRect();
		const statusBox = status.getBoundingClientRect();

		// Assert
		expect(status.textContent).toBe('Updating files…');
		expect(status.getAttribute('role')).toBe('status');
		expect(status.getAttribute('aria-live')).toBe('polite');
		expect(status.getAttribute('aria-atomic')).toBe('true');
		expect(Math.round(topbarBoxWithStatus.height)).toBe(36);
		expect(statusBox.right).toBeLessThanOrEqual(controlsBoxWithStatus.left);

		// Act
		await rendered.rerender(
			<BridgeViewerContentHeader
				controls={<button data-testid="header-proof-control">Control</button>}
				eyebrow="Files"
				statusText={null}
				title="src/app.ts"
			/>,
		);

		// Assert
		await expect
			.poll(() => document.querySelector('[data-testid="bridge-viewer-content-status"]'))
			.toBeNull();
		const topbarBoxWithoutStatus = topbar.getBoundingClientRect();
		const titleBoxWithoutStatus = title.getBoundingClientRect();
		const controlsBoxWithoutStatus = controls.getBoundingClientRect();
		expect(Math.round(topbarBoxWithoutStatus.height)).toBe(Math.round(topbarBoxWithStatus.height));
		expect(Math.round(titleBoxWithoutStatus.left)).toBe(Math.round(titleBoxWithStatus.left));
		expect(Math.round(titleBoxWithoutStatus.top)).toBe(Math.round(titleBoxWithStatus.top));
		expect(Math.round(controlsBoxWithoutStatus.left)).toBe(Math.round(controlsBoxWithStatus.left));
		expect(Math.round(controlsBoxWithoutStatus.top)).toBe(Math.round(controlsBoxWithStatus.top));
	});
});

describe('BridgeViewerContextSwitcher Browser Mode', () => {
	test('uses the owned compact toggle-group primitive at content topbar chrome scale', async () => {
		const modeChanges = vi.fn<(mode: 'file' | 'review') => void>();

		await render(
			<BridgeViewerContentHeader
				controls={<BridgeViewerContextSwitcher mode="file" onModeChange={modeChanges} />}
				eyebrow="Files"
				statusText={null}
				title="src/app.ts"
			/>,
		);

		const topbar = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-content-topbar"]'),
		);
		const switcher = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-context-switcher"]'),
		);
		const fileButton = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-context-file"]'),
		);
		const reviewButton = requireHTMLElement(
			document.querySelector('[data-testid="bridge-viewer-context-review"]'),
		);

		expect(topbar.className).toContain('h-9');
		expect(switcher.closest('[data-testid="bridge-viewer-content-topbar"]')).toBe(topbar);
		expect(switcher.getAttribute('data-slot')).toBe('toggle-group');
		expect(switcher.getAttribute('aria-label')).toBe('Bridge viewer context');
		const switcherBox = switcher.getBoundingClientRect();
		const fileButtonBox = fileButton.getBoundingClientRect();
		const reviewButtonBox = reviewButton.getBoundingClientRect();
		const railToolbarButtonTokenHeight = 24;
		const chromeControlTextSize = '11px';

		expect(Math.round(switcherBox.height)).toBe(railToolbarButtonTokenHeight);
		expect(Math.round(fileButtonBox.height)).toBe(railToolbarButtonTokenHeight);
		expect(Math.round(reviewButtonBox.height)).toBe(railToolbarButtonTokenHeight);
		expect(fileButton.getAttribute('data-slot')).toBe('button');
		expect(fileButton.getAttribute('data-toggle-group-slot')).toBe('toggle-group-item');
		expect(reviewButton.getAttribute('data-slot')).toBe('button');
		expect(reviewButton.getAttribute('data-toggle-group-slot')).toBe('toggle-group-item');
		expect(fileButton.getAttribute('aria-label')).toBe('Files');
		expect(reviewButton.getAttribute('aria-label')).toBe('Review');
		expect(fileButton.getAttribute('aria-pressed')).toBe('true');
		expect(reviewButton.getAttribute('aria-pressed')).toBe('false');
		expect(fileButton.getAttribute('data-bridge-viewer-context-selected')).toBe('true');
		expect(reviewButton.getAttribute('data-bridge-viewer-context-selected')).toBe('false');
		expect(fileButton.className).toContain('h-6');
		expect(reviewButton.className).toContain('h-6');
		expect(getComputedStyle(fileButton).fontSize).toBe(chromeControlTextSize);
		expect(getComputedStyle(reviewButton).fontSize).toBe(chromeControlTextSize);
		expect(fileButton.className).not.toContain('h-5');
		expect(reviewButton.className).not.toContain('h-5');
		expect(fileButton.textContent).toBe('Files');
		expect(reviewButton.textContent).toBe('Review');

		fileButton.click();
		expect(modeChanges).not.toHaveBeenCalled();

		reviewButton.click();
		expect(modeChanges).toHaveBeenCalledExactlyOnceWith('review');
	});
});

describe('BridgeReviewProjectionMenu Browser Mode', () => {
	test('uses the owned compact toggle-group primitive for review projection modes', async () => {
		const modeChanges = vi.fn<(mode: { readonly kind: string }) => void>();

		await render(
			<BridgeReviewProjectionMenu
				onProjectionModeChange={modeChanges}
				projectionMode={{ kind: 'normalReview' }}
			/>,
		);

		const switcher = requireHTMLElement(
			document.querySelector('[data-testid="bridge-review-mode-segmented-control"]'),
		);
		const segments = [
			...document.querySelectorAll('[data-testid="bridge-review-mode-segment"]'),
		].map(requireHTMLElement);

		expect(switcher.getAttribute('data-slot')).toBe('toggle-group');
		expect(switcher.getAttribute('role')).toBe('radiogroup');
		expect(Math.round(switcher.getBoundingClientRect().height)).toBe(24);
		expect(segments).toHaveLength(3);
		expect(segments.map((segment) => segment.getAttribute('data-slot'))).toEqual([
			'button',
			'button',
			'button',
		]);
		expect(segments.map((segment) => segment.getAttribute('data-toggle-group-slot'))).toEqual([
			'toggle-group-item',
			'toggle-group-item',
			'toggle-group-item',
		]);
		expect(segments.map((segment) => Math.round(segment.getBoundingClientRect().height))).toEqual([
			24, 24, 24,
		]);
		expect(segments.map((segment) => getComputedStyle(segment).fontSize)).toEqual([
			'11px',
			'11px',
			'11px',
		]);
		expect(segments.map((segment) => segment.getAttribute('aria-checked'))).toEqual([
			'true',
			'false',
			'false',
		]);
		expect(segments.map((segment) => segment.getAttribute('aria-pressed'))).toEqual([
			'true',
			'false',
			'false',
		]);
		expect(segments.map((segment) => segment.hasAttribute('disabled'))).toEqual([
			false,
			true,
			true,
		]);

		segments[2]?.click();
		expect(modeChanges).not.toHaveBeenCalled();
	});
});

function requireHTMLElement(element: Element | null): HTMLElement {
	expect(element).not.toBeNull();
	if (!(element instanceof HTMLElement)) {
		throw new Error('Expected HTMLElement');
	}
	return element;
}
