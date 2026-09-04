const functionalOrHexColorPattern =
	/#[\da-f]{3,8}\b|\b(?:color|hsl|hsla|lab|lch|oklab|oklch|rgb|rgba)\s*\(/giu;

const cssNamedColors = new Set(
	`aliceblue antiquewhite aqua aquamarine azure beige bisque black blanchedalmond blue blueviolet brown burlywood cadetblue chartreuse chocolate coral cornflowerblue cornsilk crimson cyan darkblue darkcyan darkgoldenrod darkgray darkgreen darkgrey darkkhaki darkmagenta darkolivegreen darkorange darkorchid darkred darksalmon darkseagreen darkslateblue darkslategray darkslategrey darkturquoise darkviolet deeppink deepskyblue dimgray dimgrey dodgerblue firebrick floralwhite forestgreen fuchsia gainsboro ghostwhite gold goldenrod gray green greenyellow grey honeydew hotpink indianred indigo ivory khaki lavender lavenderblush lawngreen lemonchiffon lightblue lightcoral lightcyan lightgoldenrodyellow lightgray lightgreen lightgrey lightpink lightsalmon lightseagreen lightskyblue lightslategray lightslategrey lightsteelblue lightyellow lime limegreen linen magenta maroon mediumaquamarine mediumblue mediumorchid mediumpurple mediumseagreen mediumslateblue mediumspringgreen mediumturquoise mediumvioletred midnightblue mintcream mistyrose moccasin navajowhite navy oldlace olive olivedrab orange orangered orchid palegoldenrod palegreen paleturquoise palevioletred papayawhip peachpuff peru pink plum powderblue purple rebeccapurple red rosybrown royalblue saddlebrown salmon sandybrown seagreen seashell sienna silver skyblue slateblue slategray slategrey snow springgreen steelblue tan teal thistle tomato turquoise violet wheat white whitesmoke yellow yellowgreen`.split(
		' ',
	),
);

const paletteReferencePattern = /var\(\s*--palette-[\w-]+/gu;

export function rawColorOccurrenceCount(value: string, includeNamedColors: boolean): number {
	functionalOrHexColorPattern.lastIndex = 0;
	let count = [...value.matchAll(functionalOrHexColorPattern)].length;
	if (includeNamedColors) {
		const valueWithoutCustomPropertyIdentifiers = value.replace(/var\(\s*--[\w-]+/gu, 'var(');
		for (const word of valueWithoutCustomPropertyIdentifiers.toLowerCase().match(/[a-z]+/gu) ??
			[]) {
			if (cssNamedColors.has(word)) {
				count += 1;
			}
		}
	}
	return count;
}

export function paletteReferenceCount(value: string): number {
	paletteReferencePattern.lastIndex = 0;
	return [...value.matchAll(paletteReferencePattern)].length;
}

export function isColorBearingCssProperty(propertyName: string): boolean {
	return (
		propertyName.startsWith('--') ||
		/(?:^|-)(?:background|border|caret|color|fill|outline|shadow|stroke)(?:-|$)/u.test(propertyName)
	);
}
