export type StyledElementKind = 'control' | 'floating-frame';

const controlComponentNames = new Set([
	'Button',
	'Checkbox',
	'CollapsibleTrigger',
	'ComboboxChip',
	'ComboboxChipsInput',
	'ComboboxClear',
	'ComboboxInput',
	'ComboboxItem',
	'ComboboxTrigger',
	'DrawerClose',
	'DrawerTrigger',
	'DropdownMenuCheckboxItem',
	'DropdownMenuItem',
	'DropdownMenuRadioItem',
	'DropdownMenuSubTrigger',
	'DropdownMenuTrigger',
	'Input',
	'InputGroupButton',
	'InputGroupInput',
	'InputGroupTextarea',
	'PopoverTrigger',
	'SelectItem',
	'SelectTrigger',
	'Textarea',
	'Toggle',
	'ToggleGroup',
	'ToggleGroupItem',
	'TooltipTrigger',
]);

const floatingFrameComponentNames = new Set([
	'ComboboxContent',
	'DrawerContent',
	'DrawerOverlay',
	'DropdownMenuContent',
	'DropdownMenuSubContent',
	'PopoverContent',
	'TooltipContent',
]);

const rawPaletteUtilityPattern =
	/^(?:bg|border|decoration|divide|fill|from|outline|ring|shadow|stroke|text|to|via)-(?:black|white|slate-\d{2,3}|gray-\d{2,3}|zinc-\d{2,3}|neutral-\d{2,3}|stone-\d{2,3}|red-\d{2,3}|orange-\d{2,3}|amber-\d{2,3}|yellow-\d{2,3}|lime-\d{2,3}|green-\d{2,3}|emerald-\d{2,3}|teal-\d{2,3}|cyan-\d{2,3}|sky-\d{2,3}|blue-\d{2,3}|indigo-\d{2,3}|violet-\d{2,3}|purple-\d{2,3}|fuchsia-\d{2,3}|pink-\d{2,3}|rose-\d{2,3})(?:\/\d+)?$/u;

const controlAppearanceUtilityPattern =
	/^(?:bg-|border(?:-|$)|duration-|fill-|font-|h-|leading-|max-h-|min-h-|opacity-|outline-|p[trblxy]?-|ring(?:-|$)|rounded(?:-|$)|shadow(?:-|$)|stroke-|text-|transition(?:-|$))/u;
const floatingAppearanceUtilityPattern =
	/^(?:bg-|border(?:-|$)|duration-|fill-|font-|leading-|opacity-|outline-|ring(?:-|$)|rounded(?:-|$)|shadow(?:-|$)|stroke-|text-|transition(?:-|$))/u;

const allowedLayoutUtilityPattern =
	/^(?:absolute|basis-|block|bottom-|box-|contents|cursor-|fixed|flex(?:-|$)|float-|gap(?:-|$)|grid(?:-|$)|grow(?:-|$)|h-|hidden|inset-|inline(?:-|$)|isolate|items-|justify-|left-|m[trblxy]?-|max-h-|max-w-|min-h-|min-w-|object-|order-|overflow(?:-|$)|peer|pointer-events-|relative|right-|rotate-|scale-|self-|shrink(?:-|$)|sr-only|static|sticky|table(?:-|$)|top-|transform(?:-|$)|translate-|truncate|visible|w-|whitespace-|z-)/u;
const layoutCustomPropertyUtilityPattern =
	/^\[--[\w-]*(?:bleed|height|inset|offset|position|width)[\w-]*:.+\]$/u;

const controlStyleProperties = new Set([
	'background',
	'backgroundColor',
	'border',
	'borderColor',
	'borderRadius',
	'borderStyle',
	'borderWidth',
	'boxShadow',
	'color',
	'font',
	'fontFamily',
	'fontSize',
	'fontStyle',
	'fontWeight',
	'height',
	'lineHeight',
	'maxHeight',
	'minHeight',
	'opacity',
	'outline',
	'outlineColor',
	'outlineOffset',
	'outlineStyle',
	'outlineWidth',
	'padding',
	'paddingBlock',
	'paddingBottom',
	'paddingInline',
	'paddingLeft',
	'paddingRight',
	'paddingTop',
]);

const floatingStyleProperties = new Set(
	[...controlStyleProperties].filter(
		(propertyName) =>
			![
				'height',
				'maxHeight',
				'minHeight',
				'padding',
				'paddingBlock',
				'paddingBottom',
				'paddingInline',
				'paddingLeft',
				'paddingRight',
				'paddingTop',
			].includes(propertyName),
	),
);

export function explicitStyledElementKind(componentName: string): StyledElementKind | null {
	if (controlComponentNames.has(componentName)) {
		return 'control';
	}
	if (floatingFrameComponentNames.has(componentName)) {
		return 'floating-frame';
	}
	return null;
}

export function utilityWithoutVariants(classToken: string): string {
	const normalizedToken = classToken.replace(/^!+/u, '');
	let bracketDepth = 0;
	let lastVariantSeparator = -1;
	for (let characterIndex = 0; characterIndex < normalizedToken.length; characterIndex += 1) {
		const character = normalizedToken.charAt(characterIndex);
		if (character === '[') {
			bracketDepth += 1;
		} else if (character === ']') {
			bracketDepth = Math.max(0, bracketDepth - 1);
		} else if (character === ':' && bracketDepth === 0) {
			lastVariantSeparator = characterIndex;
		}
	}
	return normalizedToken.slice(lastVariantSeparator + 1);
}

export function isRawPaletteUtility(classToken: string): boolean {
	return rawPaletteUtilityPattern.test(utilityWithoutVariants(classToken));
}

export function isProhibitedUtility(classToken: string, elementKind: StyledElementKind): boolean {
	const utility = utilityWithoutVariants(classToken);
	return elementKind === 'control'
		? controlAppearanceUtilityPattern.test(utility)
		: floatingAppearanceUtilityPattern.test(utility);
}

export function isKnownLayoutUtility(classToken: string): boolean {
	const utility = utilityWithoutVariants(classToken);
	return (
		allowedLayoutUtilityPattern.test(utility) || layoutCustomPropertyUtilityPattern.test(utility)
	);
}

export function isProhibitedInlineStyleProperty(
	propertyName: string,
	elementKind: StyledElementKind,
): boolean {
	return elementKind === 'control'
		? controlStyleProperties.has(propertyName)
		: floatingStyleProperties.has(propertyName);
}
