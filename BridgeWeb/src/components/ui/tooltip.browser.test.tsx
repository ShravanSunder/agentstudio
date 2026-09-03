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
	expect(tooltip.classList).toContain('bg-popover');
	expect(tooltip.classList).toContain('text-popover-foreground');
	expect(tooltip.classList).toContain('ring-1');
	expect(tooltip.classList).toContain('shadow-md');
	expect(tooltip.classList).toContain('px-2');
	expect(tooltip.classList).toContain('py-1');
	expect(tooltip.classList).toContain('rounded-lg');
});
