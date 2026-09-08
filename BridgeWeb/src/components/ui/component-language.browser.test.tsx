import { expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Observe the actual production cascade.
import '../../app/bridge-app.css';
import { Button } from './button.js';
import { InputGroup, InputGroupInput } from './input-group.js';
import { Input } from './input.js';
import { ToggleGroup, ToggleGroupItem } from './toggle-group.js';

test('quiets expanded ghost buttons without changing hover or other button variants', async () => {
	const rendered = await render(
		<div>
			<Button aria-expanded variant="ghost" data-testid="expanded-ghost">
				Collapse
			</Button>
			<Button aria-expanded variant="outline" data-testid="expanded-outline">
				Outline
			</Button>
			<Button variant="ghost" data-testid="idle-ghost">
				Action
			</Button>
		</div>,
	);
	const expanded = rendered.getByTestId('expanded-ghost').element();
	expect(getComputedStyle(expanded).backgroundColor).toBe('rgba(255, 255, 255, 0.04)');
	expect(getComputedStyle(rendered.getByTestId('expanded-outline').element()).backgroundColor).toBe(
		'rgba(255, 255, 255, 0.08)',
	);
	expect(getComputedStyle(rendered.getByTestId('idle-ghost').element()).backgroundColor).toBe(
		'rgba(0, 0, 0, 0)',
	);
	await userEvent.hover(expanded);
	await expect
		.poll(() => getComputedStyle(expanded).backgroundColor)
		.toBe('rgba(255, 255, 255, 0.08)');
	await userEvent.unhover(expanded);
	await expect
		.poll(() => getComputedStyle(expanded).backgroundColor)
		.toBe('rgba(255, 255, 255, 0.04)');
});

test('matches only the code-view scrollbar track to file chrome and preserves its thumb', async () => {
	const rendered = await render(
		<div>
			<div className="bridge-code-view-scroll-owner bridge-scrollbar" data-testid="code-scroll" />
			<div className="bridge-scrollbar" data-testid="other-scroll" />
		</div>,
	);
	const codeScroll = rendered.getByTestId('code-scroll').element();
	const otherScroll = rendered.getByTestId('other-scroll').element();
	expect(getComputedStyle(codeScroll).scrollbarColor).toContain('rgb(39, 40, 45)');
	expect(getComputedStyle(codeScroll, '::-webkit-scrollbar-track').backgroundColor).toBe(
		'rgb(39, 40, 45)',
	);
	expect(getComputedStyle(otherScroll, '::-webkit-scrollbar-track').backgroundColor).toBe(
		'rgba(0, 0, 0, 0)',
	);
	expect(getComputedStyle(codeScroll, '::-webkit-scrollbar-thumb').backgroundColor).toBe(
		getComputedStyle(otherScroll, '::-webkit-scrollbar-thumb').backgroundColor,
	);
});

test('uses coherent control roles without recoloring protected annotation and code inputs', async () => {
	const rendered = await render(
		<div className="bg-popover">
			<Button data-testid="action" variant="outline">
				Action
			</Button>
			<Input aria-label="Value" data-testid="input" />
			<ToggleGroup data-testid="track" variant="segmented" value={['selected']}>
				<ToggleGroupItem data-testid="selected" value="selected">
					Selected
				</ToggleGroupItem>
			</ToggleGroup>
			<ToggleGroup variant="segmented" value={['unavailable']}>
				<ToggleGroupItem data-testid="disabled-selected" disabled value="unavailable">
					Selected unavailable
				</ToggleGroupItem>
			</ToggleGroup>
			<div data-testid="annotation-surface" style={{ background: 'var(--annotation-surface)' }} />
			<div
				data-testid="annotation-reference"
				style={{ background: 'color-mix(in srgb, #363636 42%, #282c34)' }}
			/>
			<div data-testid="code-text" style={{ color: 'var(--code-foreground)' }} />
		</div>,
	);
	const style = (testId: string): CSSStyleDeclaration =>
		getComputedStyle(rendered.getByTestId(testId).element());
	expect.soft(style('action').color).toBe('rgb(234, 234, 234)');
	expect.soft(style('selected').color).toBe('rgb(234, 234, 234)');
	expect.soft(style('input').backgroundColor).toBe('rgba(255, 255, 255, 0.04)');
	expect.soft(style('track').backgroundColor).toBe('rgba(0, 0, 0, 0)');
	expect.soft(style('disabled-selected').opacity).toBe('1');
	expect.soft(style('disabled-selected').borderColor).not.toBe('rgba(0, 0, 0, 0)');
	expect
		.soft(style('annotation-surface').backgroundColor)
		.toBe(style('annotation-reference').backgroundColor);
	expect.soft(style('code-text').color).toBe('rgb(255, 255, 255)');
});

test('keeps selected labels and disabled selection indicators legible over the actual fill', async () => {
	const rendered = await render(
		<div className="bg-popover">
			<Button data-testid="contrast-tint" variant="tint">
				Tint action
			</Button>
			<ToggleGroup variant="segmented" value={['selected']}>
				<ToggleGroupItem data-testid="contrast-selected" value="selected">
					Selected
				</ToggleGroupItem>
			</ToggleGroup>
			<ToggleGroup variant="segmented" value={['disabled']}>
				<ToggleGroupItem data-testid="contrast-disabled" value="disabled" disabled>
					Unavailable selected
				</ToggleGroupItem>
			</ToggleGroup>
		</div>,
	);
	const selected = rendered.getByTestId('contrast-selected').element();
	const disabled = rendered.getByTestId('contrast-disabled').element();
	const tint = rendered.getByTestId('contrast-tint').element();
	expect(renderedContrast(tint, getComputedStyle(tint).color)).toBeGreaterThanOrEqual(4.5);
	expect(renderedContrast(selected, getComputedStyle(selected).color)).toBeGreaterThanOrEqual(4.5);
	expect(renderedContrast(disabled, getComputedStyle(disabled).borderColor)).toBeGreaterThanOrEqual(
		3,
	);
});

test.each(['standalone', 'grouped'] as const)(
	'retains a contrasting focus ring alongside the invalid %s field boundary',
	async (layout) => {
		const rendered = await render(
			<div className="bg-popover">
				{layout === 'grouped' ? (
					<InputGroup data-testid="invalid-group">
						<InputGroupInput
							data-testid="invalid-focused"
							aria-label="Invalid field"
							aria-invalid
						/>
					</InputGroup>
				) : (
					<Input data-testid="invalid-focused" aria-label="Invalid field" aria-invalid />
				)}
			</div>,
		);
		await userEvent.keyboard('{Tab}');
		const input = rendered.getByTestId('invalid-focused').element();
		expect(document.activeElement).toBe(input);
		const frame = layout === 'grouped' ? rendered.getByTestId('invalid-group').element() : input;
		const style = getComputedStyle(frame);
		expect(style.boxShadow).toContain('2px');
		expect(
			renderedContrast(frame, style.getPropertyValue('--tw-ring-color')),
		).toBeGreaterThanOrEqual(3);
	},
);

function renderedContrast(element: Element, foreground: string): number {
	const canvas = document.createElement('canvas');
	canvas.width = 1;
	canvas.height = 1;
	const context = canvas.getContext('2d');
	if (context === null) throw new Error('Canvas color composition unavailable.');
	const ancestors: Element[] = [];
	let ancestor: Element | null = element;
	while (ancestor !== null) {
		ancestors.unshift(ancestor);
		ancestor = ancestor.parentElement;
	}
	for (const surface of ancestors) {
		context.fillStyle = getComputedStyle(surface).backgroundColor;
		context.fillRect(0, 0, 1, 1);
	}
	const background = luminance(context.getImageData(0, 0, 1, 1).data);
	context.fillStyle = foreground;
	context.fillRect(0, 0, 1, 1);
	const text = luminance(context.getImageData(0, 0, 1, 1).data);
	return (Math.max(background, text) + 0.05) / (Math.min(background, text) + 0.05);
}

function luminance(rgba: Uint8ClampedArray): number {
	return [0.2126, 0.7152, 0.0722].reduce((sum, weight, index) => {
		const value = (rgba[index] ?? 0) / 255;
		return sum + weight * (value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
	}, 0);
}
