import { expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../../app/bridge-app.css';
import { Tooltip, TooltipContent, TooltipTrigger } from './tooltip.js';

test('renders native-parity tooltip paint from an anchored control', async () => {
	const rendered = await render(
		<Tooltip open>
			<TooltipTrigger render={<button type="button">Manage Workspace</button>} />
			<TooltipContent>Manage Workspace (⌘R)</TooltipContent>
		</Tooltip>,
	);

	const tooltip = rendered.getByText('Manage Workspace (⌘R)').element();
	expect(tooltip.getAttribute('data-slot')).toBe('tooltip-content');
	expect(tooltip.classList).toContain('pointer-events-none');
	expect(tooltip.closest('[data-slot="tooltip-trigger"]')).toBeNull();
	const style = getComputedStyle(tooltip);
	expect(style.backgroundColor).toBe('rgb(41, 41, 41)');
	expect(style.borderColor).toBe('rgb(88, 88, 92)');
	expect(style.borderRadius).toBe('8px');
	expect(style.fontSize).toBe('11px');
	expect(style.lineHeight).toBe('14px');
	expect(style.boxShadow).not.toBe('none');
});
