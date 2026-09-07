import { SearchIcon } from 'lucide-react';
import { act, type ReactElement } from 'react';
import { toast } from 'sonner';
import { expect, test } from 'vitest';
import { render } from 'vitest-browser-react';
import { userEvent } from 'vitest/browser';

// oxlint-disable-next-line import/no-unassigned-import -- Browser Mode must load production app CSS.
import '../../app/bridge-app.css';
import { Button } from './button.js';
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from './collapsible.js';
import {
	Combobox,
	ComboboxContent,
	ComboboxInput,
	ComboboxItem,
	ComboboxList,
} from './combobox.js';
import { Drawer, DrawerContent, DrawerTitle, DrawerTrigger } from './drawer.js';
import {
	DropdownMenu,
	DropdownMenuContent,
	DropdownMenuItem,
	DropdownMenuTrigger,
} from './dropdown-menu.js';
import { InputGroup, InputGroupButton, InputGroupInput } from './input-group.js';
import { Input } from './input.js';
import { Popover, PopoverContent, PopoverHeader, PopoverTitle, PopoverTrigger } from './popover.js';
import { Toaster } from './sonner.js';
import { Textarea } from './textarea.js';
import { ToggleGroup, ToggleGroupItem } from './toggle-group.js';
import { Toggle } from './toggle.js';
import { Tooltip, TooltipContent, TooltipTrigger } from './tooltip.js';

const transparentBackground = 'rgba(0, 0, 0, 0)';
const floatingBorderColor = 'rgb(88, 88, 92)';
const floatingSurfaceColor = 'rgb(50, 54, 65)';
const popoverElevation = ['black/0.45 0px 10px 24px -8px', 'black/0.35 0px 3px 8px -2px'] as const;
const contextPanelElevation = [
	'black/0.45 -10px 8px 24px -8px',
	'black/0.35 -3px 2px 8px -2px',
] as const;

test('applies the literal compact size and typography ladder to buttons and toggles', async () => {
	const rendered = await render(
		<div>
			<Button data-testid="button-xs" size="xs">
				Extra small
			</Button>
			<Button data-testid="button-sm" size="sm">
				<SearchIcon />
				Small
			</Button>
			<Button data-testid="button-default">Default</Button>
			<Button data-testid="button-lg" size="lg">
				Large
			</Button>
			<Toggle data-testid="toggle-sm" size="sm">
				<SearchIcon />
				Search
			</Toggle>
			<InputGroup data-testid="input-group" size="sm">
				<InputGroupInput aria-label="Search" />
				<InputGroupButton aria-label="Clear" data-testid="input-group-icon-xs" size="icon-xs">
					<SearchIcon />
				</InputGroupButton>
				<InputGroupButton
					aria-label="Options"
					data-testid="input-group-icon-sm"
					disabled
					size="icon-sm"
				>
					<SearchIcon />
				</InputGroupButton>
			</InputGroup>
			<ToggleGroup data-testid="segmented-group" size="xs" value={['files']} variant="segmented">
				<ToggleGroupItem data-testid="segmented-label" value="files">
					Files
				</ToggleGroupItem>
				<ToggleGroupItem data-testid="segmented-icon" size="icon-xs" value="review">
					<SearchIcon />
				</ToggleGroupItem>
			</ToggleGroup>
		</div>,
	);

	for (const [testId, expectedHeight] of [
		['button-xs', '20px'],
		['button-sm', '24px'],
		['button-default', '28px'],
		['button-lg', '32px'],
		['toggle-sm', '24px'],
	] as const) {
		const style = getComputedStyle(rendered.getByTestId(testId).element());
		expect(style.height, testId).toBe(expectedHeight);
		expect(style.fontSize, testId).toBe('11px');
		expect(style.lineHeight, testId).toBe('14px');
		expect(style.transitionDuration, testId).toBe('0.12s');
	}

	const toolbarIcon = rendered.getByTestId('button-sm').element().querySelector('svg');
	if (toolbarIcon === null) throw new Error('Expected the toolbar button to render its icon.');
	expect(getComputedStyle(toolbarIcon).width).toBe('12px');
	expect(getComputedStyle(toolbarIcon).height).toBe('12px');
	expect(getComputedStyle(rendered.getByTestId('input-group').element()).height).toBe('24px');
	expect(getComputedStyle(rendered.getByTestId('input-group-icon-xs').element()).width).toBe(
		'20px',
	);
	expect(getComputedStyle(rendered.getByTestId('input-group-icon-sm').element()).width).toBe(
		'24px',
	);
	expect(getComputedStyle(rendered.getByLabelText('Search').element()).color).not.toBe(
		getComputedStyle(rendered.getByTestId('input-group-icon-sm').element()).color,
	);
	expect(getComputedStyle(rendered.getByTestId('segmented-group').element()).height).toBe('24px');
	expect(getComputedStyle(rendered.getByTestId('segmented-label').element()).height).toBe('20px');
	expect(getComputedStyle(rendered.getByTestId('segmented-icon').element()).width).toBe('20px');
});

test('keeps neutral open paint distinct from selected toggle tint and lets disabled paint win', async () => {
	const rendered = await render(
		<div>
			<span className="border border-input" data-testid="input-border-color" />
			<span className="text-faint-foreground" data-testid="faint-foreground-color" />
			<Button aria-expanded="true" data-testid="open-button" variant="ghost">
				Open panel
			</Button>
			<Button aria-pressed="true" data-testid="pressed-button" variant="ghost">
				Pressed action
			</Button>
			<Toggle aria-pressed="true" data-testid="selected-toggle">
				Selected mode
			</Toggle>
			<Toggle aria-pressed="true" data-testid="disabled-selected-toggle" disabled>
				<SearchIcon />
				Unavailable mode
			</Toggle>
			<Button
				aria-expanded="true"
				aria-pressed="true"
				data-testid="disabled-open-button"
				disabled
				variant="outline"
			>
				<SearchIcon />
				Unavailable panel
			</Button>
			<span className="inline-flex" data-testid="disabled-primary-hover-region">
				<Button data-testid="disabled-primary-button" disabled>
					<SearchIcon />
					Unavailable primary
				</Button>
			</span>
		</div>,
	);

	const openStyle = getComputedStyle(rendered.getByTestId('open-button').element());
	const pressedStyle = getComputedStyle(rendered.getByTestId('pressed-button').element());
	const selectedStyle = getComputedStyle(rendered.getByTestId('selected-toggle').element());

	const faintForeground = getComputedStyle(
		rendered.getByTestId('faint-foreground-color').element(),
	).color;
	const inputBorder = getComputedStyle(
		rendered.getByTestId('input-border-color').element(),
	).borderColor;
	const disabledToggle = rendered.getByTestId('disabled-selected-toggle').element();
	const disabledToggleStyle = getComputedStyle(disabledToggle);
	expect(disabledToggleStyle.opacity).toBe('1');
	expect(disabledToggleStyle.backgroundColor).toBe(transparentBackground);
	expect(disabledToggleStyle.borderColor).toBe(transparentBackground);
	expect(disabledToggleStyle.color).toBe(faintForeground);
	expect(getComputedStyle(requiredSvg(disabledToggle)).color).toBe(faintForeground);

	const disabledOpenButton = rendered.getByTestId('disabled-open-button').element();
	const disabledOpenStyle = getComputedStyle(disabledOpenButton);
	expect(disabledOpenStyle.opacity).toBe('1');
	expect(disabledOpenStyle.backgroundColor).toBe(transparentBackground);
	expect(disabledOpenStyle.borderColor).toBe(inputBorder);
	expect(disabledOpenStyle.color).toBe(faintForeground);
	expect(getComputedStyle(requiredSvg(disabledOpenButton)).color).toBe(faintForeground);

	const disabledPrimary = rendered.getByTestId('disabled-primary-button').element();
	await userEvent.hover(rendered.getByTestId('disabled-primary-hover-region').element());
	await Promise.all(
		disabledPrimary.getAnimations().map((animation: Animation) => animation.finished),
	);
	const disabledPrimaryStyle = getComputedStyle(disabledPrimary);
	expect(disabledPrimaryStyle.opacity).toBe('1');
	expect(disabledPrimaryStyle.backgroundColor).not.toBe(selectedStyle.backgroundColor);
	expect(disabledPrimaryStyle.borderColor).toBe(inputBorder);
	expect(disabledPrimaryStyle.color).toBe(faintForeground);
	expect(getComputedStyle(requiredSvg(disabledPrimary)).color).toBe(faintForeground);

	expect(openStyle.backgroundColor).not.toBe(transparentBackground);
	expect(pressedStyle.backgroundColor).toBe(openStyle.backgroundColor);
	expect(pressedStyle.color).toBe(openStyle.color);
	expect(selectedStyle.backgroundColor).not.toBe(openStyle.backgroundColor);
	expect(selectedStyle.color).not.toBe(openStyle.color);
});

test('owns focus, invalid, field, and editor presentation at the primitive boundary', async () => {
	const rendered = await render(
		<div>
			<span className="bg-ring/30" data-testid="focus-ring-color" />
			<span className="border border-ring" data-testid="focus-border-color" />
			<span className="bg-destructive/20" data-testid="invalid-ring-color" />
			<Button data-testid="focused-button" variant="outline">
				Focused
			</Button>
			<Button data-testid="focused-success-button" variant="success-outline">
				Focused success
			</Button>
			<Button data-testid="focused-destructive-button" variant="destructive">
				Focused destructive
			</Button>
			<Input aria-invalid="true" data-testid="invalid-input" />
			<Input data-testid="small-input" size={undefined} />
			<Textarea data-testid="editor" />
		</div>,
	);

	const focusedButton = rendered.getByTestId('focused-button').element();
	await userEvent.keyboard('{Tab}');
	expect(document.activeElement).toBe(focusedButton);
	await Promise.all(
		focusedButton.getAnimations().map((animation: Animation) => animation.finished),
	);
	const focusedStyle = getComputedStyle(focusedButton);
	const focusRingColor = getComputedStyle(
		rendered.getByTestId('focus-ring-color').element(),
	).backgroundColor;
	const focusBorderColor = getComputedStyle(
		rendered.getByTestId('focus-border-color').element(),
	).borderColor;
	const focusedBorderColor = focusedStyle.borderColor;
	const focusedBoxShadow = focusedStyle.boxShadow;
	expect(focusedBorderColor).toBe(focusBorderColor);
	expect(focusedBoxShadow).toContain('0px 0px 0px 2px');
	expect(focusedBoxShadow).toContain(focusRingColor);
	await userEvent.keyboard('{Tab}');
	const focusedSuccessButton = rendered.getByTestId('focused-success-button').element();
	expect(document.activeElement).toBe(focusedSuccessButton);
	await Promise.all(
		focusedSuccessButton.getAnimations().map((animation: Animation) => animation.finished),
	);
	const focusedSuccessStyle = getComputedStyle(focusedSuccessButton);
	expect(focusedSuccessStyle.borderColor).toBe(focusBorderColor);
	expect(focusedSuccessStyle.boxShadow).toBe(focusedBoxShadow);

	await userEvent.keyboard('{Tab}');
	const focusedDestructiveButton = rendered.getByTestId('focused-destructive-button').element();
	expect(document.activeElement).toBe(focusedDestructiveButton);
	await Promise.all(
		focusedDestructiveButton.getAnimations().map((animation: Animation) => animation.finished),
	);
	const focusedDestructiveStyle = getComputedStyle(focusedDestructiveButton);
	expect(focusedDestructiveStyle.borderColor).toBe(focusBorderColor);
	expect(focusedDestructiveStyle.boxShadow).toBe(focusedBoxShadow);

	const invalidStyle = getComputedStyle(rendered.getByTestId('invalid-input').element());
	const invalidRingColor = getComputedStyle(
		rendered.getByTestId('invalid-ring-color').element(),
	).backgroundColor;
	expect(invalidStyle.boxShadow).toContain('0px 0px 0px 2px');
	expect(invalidStyle.boxShadow).toContain(invalidRingColor);
	expect(invalidStyle.borderColor).not.toBe('rgba(0, 0, 0, 0)');

	const inputStyle = getComputedStyle(rendered.getByTestId('small-input').element());
	expect(inputStyle.height).toBe('28px');
	expect(inputStyle.fontSize).toBe('11px');
	expect(inputStyle.lineHeight).toBe('14px');

	const editorStyle = getComputedStyle(rendered.getByTestId('editor').element());
	expect(editorStyle.minHeight).toBe('48px');
	expect(editorStyle.fontSize).toBe('12px');
	expect(editorStyle.lineHeight).toBe('16px');
});

function requiredSvg(control: Element): SVGElement {
	const icon = control.querySelector('svg');
	if (icon === null) throw new Error('Expected the control to render an SVG icon.');
	return icon;
}

test('keeps body-portaled floating primitives in the canonical frame family', async () => {
	const rendered = await render(
		<div className="dark">
			<Popover open>
				<PopoverTrigger render={<button type="button">Popover trigger</button>} />
				<PopoverContent data-testid="compact-popover">
					<PopoverHeader>
						<PopoverTitle>Popover title</PopoverTitle>
					</PopoverHeader>
					<div>Popover body</div>
				</PopoverContent>
			</Popover>
			<Tooltip open>
				<TooltipTrigger render={<button type="button">Tooltip trigger</button>} />
				<TooltipContent>Tooltip body</TooltipContent>
			</Tooltip>
		</div>,
	);

	const popover = rendered.getByTestId('compact-popover').element();
	const tooltip = rendered.getByText('Tooltip body').element();
	expect(popover.parentElement?.closest('.dark')).toBeNull();
	expect(tooltip.parentElement?.closest('.dark')).toBeNull();

	const popoverStyle = getComputedStyle(popover);
	const tooltipStyle = getComputedStyle(tooltip);
	expect(popoverStyle.animationDuration).toBe('0.12s');
	expect(tooltipStyle.animationDuration).toBe('0.12s');
	expect(popoverStyle.padding).toBe('8px');
	expect(popoverStyle.rowGap).toBe('8px');
	const titleStyle = getComputedStyle(rendered.getByText('Popover title').element());
	expect(titleStyle.fontSize).toBe('11px');
	expect(titleStyle.lineHeight).toBe('14px');
	expect(popoverStyle.backgroundColor).toBe(tooltipStyle.backgroundColor);
	expect(popoverStyle.borderColor).toBe(tooltipStyle.borderColor);
	expect(popoverStyle.borderRadius).toBe('8px');
	expect(tooltipStyle.borderRadius).toBe('8px');
	expect(popoverStyle.boxShadow).toBe(tooltipStyle.boxShadow);
	expect(popoverStyle.fontSize).toBe('12px');
	expect(tooltipStyle.fontSize).toBe('11px');
});

test('renders menu and combobox portals with the complete canonical floating frame', async () => {
	const rendered = await render(
		<div>
			<DropdownMenu open>
				<DropdownMenuTrigger render={<button type="button">Menu trigger</button>} />
				<DropdownMenuContent>
					<DropdownMenuItem>Menu action</DropdownMenuItem>
				</DropdownMenuContent>
			</DropdownMenu>
			<Combobox items={['Combobox action']} open>
				<ComboboxInput aria-label="Choose action" />
				<ComboboxContent>
					<ComboboxList>
						<ComboboxItem value="Combobox action">Combobox action</ComboboxItem>
					</ComboboxList>
				</ComboboxContent>
			</Combobox>
		</div>,
	);

	await expect.element(rendered.getByText('Menu action')).toBeVisible();
	await expect.element(rendered.getByText('Combobox action')).toBeVisible();
	const menuItem = rendered.getByText('Menu action').element();
	const comboboxItem = rendered.getByText('Combobox action').element();
	const menuFrame = requiredClosestHTMLElement(menuItem, '[data-slot="dropdown-menu-content"]');
	const comboboxFrame = requiredClosestHTMLElement(comboboxItem, '[data-slot="combobox-content"]');

	expect(menuFrame.closest('.dark')).toBeNull();
	expect(comboboxFrame.closest('.dark')).toBeNull();
	assertCanonicalFloatingFrame(menuFrame);
	assertCanonicalFloatingFrame(comboboxFrame);
	expect(getComputedStyle(menuFrame).animationDuration).toBe('0.12s');
	expect(getComputedStyle(comboboxFrame).animationDuration).toBe('0.12s');
	for (const actionRow of [menuItem, comboboxItem]) {
		const actionRowStyle = getComputedStyle(actionRow);
		expect(actionRowStyle.height).toBe('28px');
		expect(actionRowStyle.fontSize).toBe('11px');
		expect(actionRowStyle.lineHeight).toBe('14px');
	}
});

test('uses standard expansion and fast collapse motion in the shared collapsible', async () => {
	const contentForState = (open: boolean): ReactElement => (
		<Collapsible open={open}>
			<CollapsibleTrigger>Expand section</CollapsibleTrigger>
			<CollapsibleContent keepMounted>Collapsible body</CollapsibleContent>
		</Collapsible>
	);
	const rendered = await render(contentForState(true));
	const panel = rendered.getByText('Collapsible body').element();
	await act(async (): Promise<void> => {
		await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
		await Promise.all(panel.getAnimations().map((animation) => animation.finished));
	});
	expect(getComputedStyle(panel).transitionDuration).toBe('0.2s');
	let closingDuration: string | null = null;
	const closingObserver = new MutationObserver((): void => {
		if (panel.hasAttribute('data-ending-style')) {
			closingDuration = getComputedStyle(panel).transitionDuration;
		}
	});
	closingObserver.observe(panel, { attributes: true });
	try {
		await rendered.rerender(contentForState(false));
		for (let remainingFrames = 60; remainingFrames > 0; remainingFrames -= 1) {
			if (panel.hasAttribute('hidden')) break;
			await act(async (): Promise<void> => {
				await new Promise<void>((resolve) => requestAnimationFrame(() => resolve()));
			});
		}
		expect(panel.hasAttribute('hidden')).toBe(true);
		expect(closingDuration).toBe('0.12s');
	} finally {
		closingObserver.disconnect();
	}
});

test('renders a context drawer with the permitted directional floating frame', async () => {
	const rendered = await render(
		<Drawer modal={false} open swipeDirection="right">
			<DrawerTrigger render={<button type="button">Drawer trigger</button>} />
			<DrawerContent frame="context-panel">
				<DrawerTitle>Context panel title</DrawerTitle>
			</DrawerContent>
		</Drawer>,
	);

	await expect.element(rendered.getByText('Context panel title')).toBeVisible();
	const title = rendered.getByText('Context panel title').element();
	const drawerFrame = requiredClosestHTMLElement(title, '[data-slot="drawer-popup"]');
	const drawerStyle = getComputedStyle(drawerFrame);
	expect(drawerFrame.closest('.dark')).toBeNull();
	expect(drawerStyle.backgroundColor).toBe(floatingSurfaceColor);
	expect(drawerStyle.borderColor).toBe(floatingBorderColor);
	expect(drawerStyle.borderRadius).toBe('14px');
	expect(normalizedVisibleBlackShadows(drawerStyle.boxShadow)).toEqual(contextPanelElevation);
	expect(getComputedStyle(title).fontFamily).toBe(drawerStyle.fontFamily);
});

test('renders Sonner toast title and description in the canonical floating frame', async () => {
	const rendered = await render(<Toaster duration={Number.POSITIVE_INFINITY} />);
	let toastId: string | number | undefined;
	await act(async (): Promise<void> => {
		toastId = toast('Toast title', {
			description: 'Toast description',
		});
	});

	await expect.element(rendered.getByText('Toast title')).toBeVisible();
	await expect.element(rendered.getByText('Toast description')).toBeVisible();
	const title = rendered.getByText('Toast title').element();
	const description = rendered.getByText('Toast description').element();
	const toastFrame = requiredClosestHTMLElement(title, '[data-sonner-toast]');
	assertCanonicalFloatingFrame(toastFrame);
	const titleStyle = getComputedStyle(title);
	const descriptionStyle = getComputedStyle(description);
	expect(titleStyle.fontSize).toBe('11px');
	expect(titleStyle.lineHeight).toBe('14px');
	expect(descriptionStyle.fontSize).toBe('9px');
	expect(descriptionStyle.lineHeight).toBe('12px');
	await act(async (): Promise<void> => {
		toast.dismiss(toastId);
	});
});

function assertCanonicalFloatingFrame(frame: HTMLElement): void {
	const style = getComputedStyle(frame);
	expect(style.backgroundColor).toBe(floatingSurfaceColor);
	expect(style.borderColor).toBe(floatingBorderColor);
	expect(style.borderRadius).toBe('8px');
	expect(normalizedVisibleBlackShadows(style.boxShadow)).toEqual(popoverElevation);
}

function normalizedVisibleBlackShadows(boxShadow: string): readonly string[] {
	const shadowLayers = boxShadow.match(/(?:rgba|color)\([^)]*\) [^,]+/gu) ?? [];
	return shadowLayers
		.filter(
			(shadowLayer) =>
				!shadowLayer.startsWith('rgba(0, 0, 0, 0)') &&
				!shadowLayer.startsWith('color(srgb 0 0 0 / 0)'),
		)
		.map((shadowLayer) =>
			shadowLayer
				.replace(/^rgba\(0, 0, 0, ([^)]+)\)/u, 'black/$1')
				.replace(/^color\(srgb 0 0 0 \/ ([^)]+)\)/u, 'black/$1'),
		);
}

function requiredClosestHTMLElement(element: Element, selector: string): HTMLElement {
	const closestElement = element.closest(selector);
	if (!(closestElement instanceof HTMLElement)) {
		throw new Error(`Expected element to be inside ${selector}.`);
	}
	return closestElement;
}
