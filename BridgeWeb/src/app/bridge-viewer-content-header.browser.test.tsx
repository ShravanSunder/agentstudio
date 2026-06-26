import { describe, expect, test, vi } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load the app CSS.
import './bridge-app.css';
import {
	BridgeViewerContentHeader,
	BridgeViewerContextSwitcher,
} from './bridge-viewer-content-header.js';

describe('BridgeViewerContextSwitcher Browser Mode', () => {
	test('uses the owned compact toggle-group primitive at content topbar chrome scale', async () => {
		const modeChanges = vi.fn<(mode: 'file' | 'review') => void>();

		render(
			<BridgeViewerContentHeader
				controls={<BridgeViewerContextSwitcher mode="file" onModeChange={modeChanges} />}
				eyebrow="Files"
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
		expect(switcher.className).toContain('h-6');
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
		expect(fileButton.className).toContain('h-5');
		expect(fileButton.className).toContain('w-5');
		expect(reviewButton.className).toContain('h-5');
		expect(reviewButton.className).toContain('w-5');
		expect(fileButton.className).not.toContain('h-6');
		expect(reviewButton.className).not.toContain('h-6');
		expect(fileButton.textContent).toBe('');
		expect(reviewButton.textContent).toBe('');

		fileButton.click();
		expect(modeChanges).not.toHaveBeenCalled();

		reviewButton.click();
		expect(modeChanges).toHaveBeenCalledExactlyOnceWith('review');
	});
});

function requireHTMLElement(element: Element | null): HTMLElement {
	expect(element).not.toBeNull();
	if (!(element instanceof HTMLElement)) {
		throw new Error('Expected HTMLElement');
	}
	return element;
}
