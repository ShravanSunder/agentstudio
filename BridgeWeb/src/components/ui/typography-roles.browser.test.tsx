import { act } from 'react';
import { expect, test } from 'vitest';
import { render } from 'vitest-browser-react';

// oxlint-disable-next-line import/no-unassigned-import -- Exercise the production cascade.
import '../../app/bridge-app.css';
import { bridgeViewerTreeStyle } from '../../app/bridge-viewer-tree-theme.js';
import { Button } from './button.js';
import { Combobox, ComboboxItem, ComboboxItemDescription, ComboboxList } from './combobox.js';
import { InputGroup, InputGroupInput } from './input-group.js';
import { Input } from './input.js';
import { ItemContent, ItemLabel } from './item-content.js';

test('uses native-correlated roles instead of one dense size for every kind of text', async () => {
	const rendered = await render(
		<div>
			<Button data-testid="compact-action">Retry</Button>
			<Input aria-label="Field value" data-testid="field-value" />
			<InputGroup>
				<InputGroupInput aria-label="Search" data-testid="search-value" />
			</InputGroup>
			<div data-testid="tree-host" style={bridgeViewerTreeStyle} />
			<Combobox inline items={['branch']} open value="branch">
				<ComboboxList>
					<ComboboxItem data-testid="descriptive-row" presentation="descriptive" value="branch">
						<ItemContent>
							<ItemLabel data-testid="list-name">A branch name</ItemLabel>
							<ComboboxItemDescription data-testid="list-description">
								Remote-tracking
							</ComboboxItemDescription>
						</ItemContent>
					</ComboboxItem>
				</ComboboxList>
			</Combobox>
		</div>,
	);
	const style = (testId: string): CSSStyleDeclaration =>
		getComputedStyle(rendered.getByTestId(testId).element());
	expect(style('field-value').fontSize).toBe('12px');
	expect(style('search-value').fontSize).toBe('12px');
	expect(style('compact-action').fontSize).toBe('11px');
	expect(style('list-name').fontSize).toBe('13px');
	expect(style('list-name').lineHeight).toBe('18px');
	expect(style('list-description').fontSize).toBe('12px');
	expect(style('list-description').lineHeight).toBe('16px');
	expect(style('descriptive-row').height).toBe('44px');
	expect(style('tree-host').getPropertyValue('--trees-font-size-override').trim()).toBe('13px');
	expect(style('list-name').fontFamily).toBe(style('field-value').fontFamily);
});

test('reserves indicator space for long names and metadata in a narrow descriptive list', async () => {
	const label = 'a-very-long-branch-name/'.repeat(12);
	const rendered = await render(
		<div style={{ width: 240 }}>
			<Combobox inline items={['branch']} open value="branch">
				<ComboboxList>
					<ComboboxItem data-testid="narrow-row" presentation="descriptive" value="branch">
						<ItemContent>
							<ItemLabel data-testid="narrow-label">{label}</ItemLabel>
							<ComboboxItemDescription data-testid="narrow-description">
								{'Long metadata '.repeat(20)}
							</ComboboxItemDescription>
						</ItemContent>
					</ComboboxItem>
				</ComboboxList>
			</Combobox>
		</div>,
	);
	await act(async (): Promise<void> => {
		await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
	});
	const rowBounds = rendered.getByTestId('narrow-row').element().getBoundingClientRect();
	for (const testId of ['narrow-label', 'narrow-description']) {
		const bounds = rendered.getByTestId(testId).element().getBoundingClientRect();
		expect(bounds.right).toBeLessThanOrEqual(rowBounds.right - 32);
		expect(bounds.bottom).toBeLessThanOrEqual(rowBounds.bottom);
	}
	expect(rendered.getByTestId('narrow-label').element().textContent).toBe(label);
});
