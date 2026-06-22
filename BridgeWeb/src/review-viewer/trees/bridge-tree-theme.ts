import { themeToTreeStyles, type TreeThemeInput, type TreeThemeStyles } from '@pierre/trees';

export const bridgeCatppuccinMochaTreeTheme = {
	type: 'dark',
	fg: '#CDD6F4',
	bg: '#1E1E2E',
	colors: {
		descriptionForeground: '#6C7086',
		focusBorder: '#B4BEFE',
		'editor.background': '#1E1E2E',
		'editor.foreground': '#CDD6F4',
		'gitDecoration.addedResourceForeground': '#A6E3A1',
		'gitDecoration.deletedResourceForeground': '#F38BA8',
		'gitDecoration.modifiedResourceForeground': '#89B4FA',
		'input.background': '#181825',
		'list.activeSelectionBackground': '#45475A',
		'list.activeSelectionForeground': '#CDD6F4',
		'list.focusOutline': '#00000000',
		'list.hoverBackground': '#313244',
		'sideBar.background': '#181825',
		'sideBar.foreground': '#CDD6F4',
		'sideBarSectionHeader.foreground': '#BAC2DE',
	},
} as const satisfies TreeThemeInput;

export const bridgeCatppuccinMochaTreeStyles: TreeThemeStyles = themeToTreeStyles(
	bridgeCatppuccinMochaTreeTheme,
);
