import { act } from 'react';
import { expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Verify production styling.
import '../../app/bridge-app.css';
import { ResizableHandle, ResizablePanel, ResizablePanelGroup } from './resizable.js';

test('keeps a quiet line with reachable nearby pointer and keyboard resizing', async () => {
	const rendered = await render(
		<div style={{ width: 800, height: 300 }}>
			<ResizablePanelGroup>
				<ResizablePanel id="content" defaultSize="70%" minSize="20%">
					<div>Content</div>
				</ResizablePanel>
				<ResizableHandle id="test-resize" aria-label="Resize panels" withHandle />
				<ResizablePanel id="tree" minSize="20%">
					<div>Tree</div>
				</ResizablePanel>
			</ResizablePanelGroup>
		</div>,
	);
	const handle = rendered.getByRole('separator', { name: 'Resize panels' }).element();
	expect(handle.getBoundingClientRect().width).toBe(1);
	expect(getComputedStyle(handle).backgroundColor).toBe('rgba(255, 255, 255, 0.1)');
	const grip = handle.firstElementChild;
	if (grip === null) throw new Error('Expected resize grip');
	expect(getComputedStyle(grip).opacity).toBe('0');
	const box = handle.getBoundingClientRect();
	const before = Number(handle.getAttribute('aria-valuenow'));
	await act(async () => {
		const target = document.elementFromPoint(box.x + 6, box.y + 120);
		if (target === null) throw new Error('Missing near-divider target');
		target.dispatchEvent(
			new PointerEvent('pointerdown', {
				bubbles: true,
				clientX: box.x + 6,
				clientY: box.y + 120,
				pointerId: 1,
				pointerType: 'mouse',
				buttons: 1,
			}),
		);
		document.dispatchEvent(
			new PointerEvent('pointermove', {
				bubbles: true,
				clientX: box.x - 60,
				clientY: box.y + 120,
				pointerId: 1,
				pointerType: 'mouse',
				buttons: 1,
			}),
		);
		document.dispatchEvent(
			new PointerEvent('pointerup', {
				bubbles: true,
				clientX: box.x - 60,
				clientY: box.y + 120,
				pointerId: 1,
				pointerType: 'mouse',
			}),
		);
		await expect.poll(() => Number(handle.getAttribute('aria-valuenow'))).toBeLessThan(before);
	});
	await act(async () => {
		handle.focus();
	});
	await act(async (): Promise<void> => {
		// Real layout observations can update Separator ARIA while the visual state settles.
		await expect.element(handle).toHaveAttribute('data-separator', 'focus');
		await expect.poll(() => getComputedStyle(grip).opacity).toBe('1');
	});
	expect(getComputedStyle(handle).backgroundColor).toBe('rgb(143, 152, 168)');
	const pointerValue = Number(handle.getAttribute('aria-valuenow'));
	await act(async () => {
		await userEvent.keyboard('{ArrowRight}');
		await expect
			.poll(() => Number(handle.getAttribute('aria-valuenow')))
			.toBeGreaterThan(pointerValue);
	});
	await act(async (): Promise<void> => {
		handle.blur();
		await rendered.unmount();
	});
});
