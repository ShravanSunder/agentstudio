import type { ReactElement } from 'react';
import { createPortal } from 'react-dom';
import { expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Compare actual production cascade.
import '../../app/bridge-app.css';
import { BridgeViewerAppShell } from '../../app/bridge-viewer-app-shell.js';
import { Button } from './button.js';
import { Input } from './input.js';
import { Toggle } from './toggle.js';

test('renders identical control states inside the real shell and outside it in a body portal', async () => {
	// Arrange: the same primitive/state pairs cross the actual shell ownership boundary.
	const controls = (location: string): ReactElement => (
		<div data-testid={`parity-${location}`}>
			<Button size="sm" variant="outline">
				Rest
			</Button>
			<Button aria-expanded size="sm" variant="outline">
				Open
			</Button>
			<Button aria-expanded disabled size="sm" variant="outline">
				Disabled open
			</Button>
			<Toggle aria-pressed size="sm">
				Selected
			</Toggle>
			<Toggle aria-pressed disabled size="sm">
				Disabled selected
			</Toggle>
			<Input aria-invalid aria-label={`${location} invalid field`} size="sm" />
		</div>
	);
	const rendered = await render(
		<BridgeViewerAppShell appOwner="BridgeApp" mode="review">
			{controls('shell')}
			{createPortal(controls('portal'), document.body)}
		</BridgeViewerAppShell>,
	);
	const shellGroup = rendered.getByTestId('parity-shell').element();
	const portalGroup = rendered.getByTestId('parity-portal').element();

	// Act: resolve browser styles independently for both placements.
	const shellControls = shellGroup.querySelectorAll('button,input');
	const portalControls = portalGroup.querySelectorAll('button,input');

	// Assert: ancestry cannot change geometry, typography, or any tested state paint.
	expect(shellGroup.closest('[data-bridge-viewer-shell-owner]')).not.toBeNull();
	expect(portalGroup.closest('[data-bridge-viewer-shell-owner]')).toBeNull();
	expect(portalGroup.parentElement).toBe(document.body);
	expect(shellControls).toHaveLength(6);
	expect(portalControls).toHaveLength(shellControls.length);
	for (const [index, shellControl] of [...shellControls].entries()) {
		const portalControl = portalControls.item(index);
		const shellStyle = getComputedStyle(shellControl);
		const portalStyle = getComputedStyle(portalControl);
		for (const property of [
			'backgroundColor',
			'borderColor',
			'borderWidth',
			'borderRadius',
			'boxShadow',
			'color',
			'fontFamily',
			'fontSize',
			'lineHeight',
			'height',
			'opacity',
			'paddingTop',
			'paddingRight',
			'paddingBottom',
			'paddingLeft',
		] as const) {
			expect(portalStyle[property], `${index}: ${property}`).toBe(shellStyle[property]);
		}
		expect(portalStyle.height).toBe('24px');
		expect(portalStyle.fontSize).toBe(portalControl.tagName === 'INPUT' ? '12px' : '11px');
		expect(portalStyle.opacity).toBe('1');
	}
});
