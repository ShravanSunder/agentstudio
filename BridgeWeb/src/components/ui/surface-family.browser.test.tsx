import { act } from 'react';
import { expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { page, userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Exercise production token recipes.
import '../../app/bridge-app.css';
import { Combobox, ComboboxInput, ComboboxList, ComboboxItem } from './combobox.js';
import { InputGroup, InputGroupInput } from './input-group.js';
import { Input } from './input.js';

test('coordinates floating and tree search without changing their protected canvases', async () => {
	const rendered = await render(
		<div className="flex gap-4 p-4">
			<div className="w-80 bg-popover p-3" data-testid="floating">
				<div className="bg-card p-2 text-card-foreground" data-testid="card">
					Summary card
				</div>
				<Input aria-label="Commit" data-testid="standalone" />
				<Combobox inline open items={['main', 'feature']} defaultValue="main">
					<ComboboxInput aria-label="Search branches" showTrigger={false} />
					<ComboboxList>
						<ComboboxItem value="main">main</ComboboxItem>
						<ComboboxItem value="feature">feature</ComboboxItem>
					</ComboboxList>
				</Combobox>
			</div>
			<div className="w-80 bg-sidebar p-3" data-testid="tree">
				<InputGroup data-testid="tree-search">
					<InputGroupInput aria-label="Search files" />
				</InputGroup>
			</div>
			<div className="bg-background" data-testid="canvas" />
		</div>,
	);
	const style = (id: string): CSSStyleDeclaration =>
		getComputedStyle(rendered.getByTestId(id).element());
	expect(style('floating').backgroundColor).toBe('rgb(28, 32, 38)');
	expect(style('card').backgroundColor).toBe('rgb(39, 44, 52)');
	await act(async (): Promise<void> => {
		(rendered.getByTestId('floating').element() as HTMLElement).style.setProperty(
			'--card',
			'rgb(70, 71, 76)',
		);
	});
	expect(style('card').backgroundColor).toBe('rgb(70, 71, 76)');
	expect(style('floating').backgroundColor).toBe('rgb(28, 32, 38)');
	await act(async (): Promise<void> => {
		(rendered.getByTestId('floating').element() as HTMLElement).style.removeProperty('--card');
	});
	expect(style('standalone').backgroundColor).toBe('rgb(20, 24, 30)');
	expect(style('tree-search').backgroundColor).toBe(style('standalone').backgroundColor);
	expect(style('tree').backgroundColor).toBe('rgb(28, 32, 38)');
	expect(style('canvas').backgroundColor).toBe('rgb(40, 44, 52)');
	await act(async () => {
		await rendered.getByRole('textbox', { name: 'Search files' }).click();
	});
	await expect.poll(() => style('tree-search').borderColor).toBe('rgb(110, 119, 135)');
	expect(style('tree-search').boxShadow).toContain('rgb(143, 152, 168)');
	await act(async () => {
		await rendered.getByRole('combobox', { name: 'Search branches' }).click();
	});
	await act(async () => {
		await userEvent.keyboard('{ArrowDown}');
	});
	await act(async () => {
		await userEvent.keyboard('{ArrowDown}');
	});
	const highlighted = document.querySelector('[data-slot="combobox-item"][data-highlighted]');
	if (!(highlighted instanceof HTMLElement))
		throw new Error('Expected keyboard-highlighted option.');
	expect(highlighted.textContent).toBe('feature');
	const selectedIndicator = rendered
		.getByRole('option', { name: 'main', exact: true })
		.element()
		.querySelector('svg');
	expect(selectedIndicator?.getBoundingClientRect().width).toBeGreaterThan(0);
	expect(getComputedStyle(highlighted).backgroundColor).toBe('rgb(62, 70, 82)');
	expect(getComputedStyle(highlighted).boxShadow).toContain('rgb(143, 152, 168)');
	await page.screenshot({ path: '../../../../tmp/bridgeweb-surface-family-trial.png' });
});
