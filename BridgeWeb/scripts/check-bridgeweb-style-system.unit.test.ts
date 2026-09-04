import { mkdir, mkdtemp, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';

import { describe, expect, test } from 'vitest';

import type { StyleSystemReport } from './check-bridgeweb-style-system-model.ts';
import {
	type CheckBridgeWebStyleSystemProps,
	checkBridgeWebStyleSystem,
} from './check-bridgeweb-style-system.ts';

const canonicalCss = `
:root {
	/* @design-primitives:start */
	--palette-canvas: #282c34;
	--palette-primary: #409cff;
	--palette-wash: rgb(255 255 255 / 0.1);
	/* @design-primitives:end */
	--background: var(--palette-canvas);
}
@layer base { button, input, textarea { font: inherit; } }
`;

const canonicalMirror = `
export const bridgeDesignPalette = {
	'--palette-canvas': '#282c34',
	'--palette-primary': '#409cff',
	'--palette-wash': 'rgb(255 255 255 / 0.1)',
} as const satisfies Readonly<Record<\`--palette-\${string}\`, string>>;
`;

describe('BridgeWeb style-system checker', () => {
	test('accepts canonical sources and named non-control presentation', async () => {
		const report = await checkFixture({
			'src/app/layout.tsx': `
				export const Layout = () => <section className="grid h-full gap-2 text-muted-foreground" />;
			`,
			'src/app/status.tsx': `
				export const Status = () => <span className="text-destructive size-3" />;
			`,
			'src/app/loading.tsx': `
				export const Loading = () => <div inert className="opacity-50 h-full" />;
			`,
			'src/review-viewer/code-view/pierre-metrics.ts': `
				export const pierreMetrics = { fontSize: 12, lineHeight: 16 };
			`,
		});

		expect(report).toEqual({ ok: true, findings: [] });
	});

	test('reports every raw color and bridge alias occurrence without count allowances', async () => {
		const report = await checkFixture({
			'src/app/first.ts': `export const first = '#abcdef'; export const alias = 'var(--bridge-old)';`,
			'src/app/second.css': `.one { color: #123456; } .two { --bridge-old: red; }`,
			'src/app/raw-color.unit.test.ts': `export const fixture = '#fedcba';`,
		});

		expect(rulePaths(report, 'raw-color')).toEqual([
			'src/app/first.ts',
			'src/app/second.css',
			'src/app/second.css',
		]);
		expect(rulePaths(report, 'bridge-alias')).toEqual(['src/app/first.ts', 'src/app/second.css']);
	});

	test('fails a same-count palette replacement and duplicate mirror keys', async () => {
		const report = await checkFixture(
			{},
			{
				mirrorSource: canonicalMirror
					.replace("'--palette-primary': '#409cff'", "'--palette-accent': '#409cff'")
					.replace(
						"'--palette-wash': 'rgb(255 255 255 / 0.1)'",
						"'--palette-canvas': 'rgb(255 255 255 / 0.1)'",
					),
			},
		);

		expect(report.findings.filter(({ ruleId }) => ruleId === 'palette-parity')).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ message: expect.stringContaining('duplicate') }),
				expect.objectContaining({ message: expect.stringContaining('--palette-primary') }),
				expect.objectContaining({ message: expect.stringContaining('--palette-accent') }),
			]),
		);
	});

	test('detects appearance branches but not Pierre dark and light theme object keys', async () => {
		const report = await checkFixture({
			'src/app/theme.tsx': `
				export const pierreThemes = { dark: theme, light: theme };
				const appearanceRecipe = 'dark:bg-background';
				export const View = () => <div className={appearanceRecipe} />;
			`,
			'src/app/theme.css': `
				.dark .panel { color: var(--foreground); }
				@media (prefers-color-scheme: dark) { .panel { display: block; } }
			`,
		});

		expect(rulePaths(report, 'appearance-conditional')).toEqual([
			'src/app/theme.css',
			'src/app/theme.css',
			'src/app/theme.tsx',
		]);
	});

	test('follows aliased control imports and shared class constants through cn conditionals', async () => {
		const report = await checkFixture({
			'src/components/ui/button.tsx': `export function Button() { return null; }`,
			'src/app/control-styles.ts': `
				export const dangerousControlClassName = 'h-8 text-sm hover:bg-accent';
			`,
			'src/app/action.tsx': `
				import { Button as ActionControl } from '../components/ui/button.js';
				import { dangerousControlClassName as sharedRecipe } from './control-styles.js';
				import { cn } from '../lib/utils.js';
				export const Action = ({ active }: { active: boolean }) => (
					<ActionControl className={cn(sharedRecipe, active && 'border-primary')} />
				);
			`,
		});

		expect(report.findings.filter(({ ruleId }) => ruleId === 'control-style-override')).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ message: expect.stringContaining('h-8') }),
				expect.objectContaining({ message: expect.stringContaining('hover:bg-accent') }),
				expect.objectContaining({ message: expect.stringContaining('border-primary') }),
			]),
		);
	});

	test('detects local wrappers and compound Base UI render buttons', async () => {
		const report = await checkFixture({
			'src/components/ui/button.tsx': `export function Button() { return null; }`,
			'src/app/wrappers.tsx': `
				import { Button } from '../components/ui/button.js';
				export function ViewerAction(props: { className?: string }) {
					return <Button {...props} />;
				}
			`,
			'src/app/view.tsx': `
				import { ViewerAction as ImportedViewerAction } from './wrappers.js';
				export const View = () => (
					<>
						<ImportedViewerAction className="rounded-xl px-4" />
						<Menu.Trigger render={<button className="h-7 bg-primary" />} />
					</>
				);
			`,
		});

		expect(
			report.findings.filter(({ ruleId }) => ruleId === 'control-style-override'),
		).toHaveLength(4);
	});

	test('classifies explicit compound controls and floating frames without taking layout ownership', async () => {
		const report = await checkFixture({
			'src/components/ui/dropdown-menu.tsx': `
				export const DropdownMenuCheckboxItem = () => null;
				export const DropdownMenuRadioItem = () => null;
				export const DropdownMenuContent = () => null;
			`,
			'src/components/ui/toggle-group.tsx': `
				export const ToggleGroup = () => null;
				export const ToggleGroupItem = () => null;
			`,
			'src/components/ui/combobox.tsx': `export const ComboboxItem = () => null;`,
			'src/app/compound-controls.tsx': `
				import { DropdownMenuCheckboxItem, DropdownMenuContent, DropdownMenuRadioItem } from '../components/ui/dropdown-menu.js';
				import { ToggleGroup, ToggleGroupItem } from '../components/ui/toggle-group.js';
				import { ComboboxItem } from '../components/ui/combobox.js';
				export const View = () => <>
					<DropdownMenuCheckboxItem className="text-blue-600" />
					<DropdownMenuRadioItem className="h-9" />
					<ToggleGroup className="rounded-xl" />
					<ToggleGroupItem className="self-end px-4" />
					<ComboboxItem className="hover:bg-red-500" />
					<DropdownMenuContent className="w-80 h-[50vh] translate-x-2 data-[swipe-axis=x]:[--bleed:0px] data-[swipe-axis=x]:[--drawer-content-width:min(384px,calc(100%_-_32px))] bg-black shadow-xl" />
				</>;
			`,
		});

		expect(report.findings).toEqual(
			expect.arrayContaining([
				expect.objectContaining({
					ruleId: 'raw-color',
					message: expect.stringContaining('blue-600'),
				}),
				expect.objectContaining({
					ruleId: 'raw-color',
					message: expect.stringContaining('red-500'),
				}),
				expect.objectContaining({
					ruleId: 'raw-color',
					message: expect.stringContaining('bg-black'),
				}),
				expect.objectContaining({
					ruleId: 'control-style-override',
					message: expect.stringContaining('h-9'),
				}),
				expect.objectContaining({
					ruleId: 'control-style-override',
					message: expect.stringContaining('rounded-xl'),
				}),
				expect.objectContaining({
					ruleId: 'control-style-override',
					message: expect.stringContaining('px-4'),
				}),
				expect.objectContaining({
					ruleId: 'control-style-override',
					message: expect.stringContaining('shadow-xl'),
				}),
			]),
		);
		expect(report.findings.map(({ message }) => message).join('\n')).not.toMatch(
			/w-80|h-\[50vh\]|translate-x-2|self-end|--bleed|--drawer-content-width/u,
		);
	});

	test('checks inline control styles and native role buttons while preserving layout width', async () => {
		const report = await checkFixture({
			'src/components/ui/button.tsx': `export function Button() { return null; }`,
			'src/app/inline-styles.tsx': `
				import { Button } from '../components/ui/button.js';
				export const View = () => <>
					<Button style={{ width: 240, fontSize: 99, backgroundColor: 'var(--primary)' }} />
					<div role="button" className="h-9 bg-primary" style={{ marginLeft: 4, borderRadius: 12 }} />
				</>;
			`,
		});

		expect(report.findings.filter(({ ruleId }) => ruleId === 'control-style-override')).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ message: expect.stringContaining('fontSize') }),
				expect.objectContaining({ message: expect.stringContaining('backgroundColor') }),
				expect.objectContaining({ message: expect.stringContaining('h-9') }),
				expect.objectContaining({ message: expect.stringContaining('bg-primary') }),
				expect.objectContaining({ message: expect.stringContaining('borderRadius') }),
			]),
		);
		expect(report.findings.map(({ message }) => message).join('\n')).not.toMatch(
			/width|marginLeft/u,
		);
	});

	test('checks canonical CSS control declarations outside the base reset', async () => {
		const report = await checkFixture(
			{},
			{ cssSource: `${canonicalCss}\nbutton { font-size: 99px; }` },
		);

		expect(report.findings).toContainEqual(
			expect.objectContaining({
				ruleId: 'control-style-override',
				relativePath: 'src/app/bridge-app.css',
			}),
		);
	});

	test('resolves custom CSS classes used by controls and fails unknown custom recipes closed', async () => {
		const report = await checkFixture({
			'src/components/ui/button.tsx': `export function Button() { return null; }`,
			'src/app/control-recipes.css': `.painted-action { color: var(--primary); padding: 4px; }`,
			'src/app/custom-control.tsx': `
				import { Button } from '../components/ui/button.js';
				export const View = () => <>
					<Button className="painted-action flex ml-2 w-full" />
					<Button className="unresolved-action" />
				</>;
			`,
		});

		expect(report.findings).toEqual(
			expect.arrayContaining([
				expect.objectContaining({
					ruleId: 'control-style-override',
					message: expect.stringContaining('painted-action'),
				}),
				expect.objectContaining({
					ruleId: 'unknown-control-classes',
					message: expect.stringContaining('unresolved-action'),
				}),
			]),
		);
		expect(report.findings.map(({ message }) => message).join('\n')).not.toMatch(
			/flex|ml-2|w-full/u,
		);
	});

	test('inspects unsafeCSS strings for raw and conditional appearance while permitting Pierre metrics', async () => {
		const report = await checkFixture({
			'src/review-viewer/code-view/options.ts': `
				export const options = {
					unsafeCSS: '.dark .line { color: #abcdef; } @media (prefers-color-scheme: light) { .line { display: block; } } .virtualizer { transform: translateY(4px); }',
				};
			`,
		});

		expect(report.findings).toEqual(
			expect.arrayContaining([
				expect.objectContaining({ ruleId: 'raw-color' }),
				expect.objectContaining({
					ruleId: 'appearance-conditional',
					message: expect.stringContaining('.dark'),
				}),
				expect.objectContaining({
					ruleId: 'appearance-conditional',
					message: expect.stringContaining('prefers-color-scheme'),
				}),
			]),
		);
		expect(report.findings.map(({ message }) => message).join('\n')).not.toContain('transform');
	});

	test('fails closed for unknown dynamic control classes', async () => {
		const report = await checkFixture({
			'src/components/ui/button.tsx': `export function Button() { return null; }`,
			'src/app/action.tsx': `
				import { Button } from '../components/ui/button.js';
				export const Action = ({ recipe }: { recipe: string }) => <Button className={recipe} />;
			`,
		});

		expect(report.findings).toContainEqual(
			expect.objectContaining({
				ruleId: 'unknown-control-classes',
				relativePath: 'src/app/action.tsx',
			}),
		);
	});

	test('checks interpolated template heads, middles, and tails for literal policies', async () => {
		const report = await checkFixture({
			'src/app/template-policies.ts': `
				const value = 'resolved';
				export const first = \`#abcdef \${value} var(--bridge-middle)\`;
				export const second = \`var(--bridge-head) \${value} rgb(1 2 3)\`;
			`,
		});

		expect(rulePaths(report, 'raw-color')).toEqual([
			'src/app/template-policies.ts',
			'src/app/template-policies.ts',
		]);
		expect(rulePaths(report, 'bridge-alias')).toEqual([
			'src/app/template-policies.ts',
			'src/app/template-policies.ts',
		]);
	});

	test('resolves unsafeCSS identifiers and cva variant output for appearance policy', async () => {
		const report = await checkFixture({
			'src/app/appearance.tsx': `
				import { cva } from 'class-variance-authority';
				const embeddedPierreCss = '.dark .line { color: var(--foreground); }';
				export const options = { unsafeCSS: embeddedPierreCss };
				const appearanceVariants = cva('', {
					variants: { appearance: { dark: 'dark:bg-background', fixed: 'bg-background' } },
				});
				export const View = () => <div className={appearanceVariants({ appearance: 'dark' })} />;
			`,
		});

		expect(rulePaths(report, 'appearance-conditional')).toEqual([
			'src/app/appearance.tsx',
			'src/app/appearance.tsx',
		]);
	});

	test('inspects static styling spreads, rejects unknown styling spreads, and preserves typed attribute-only spreads', async () => {
		const report = await checkFixture({
			'src/components/ui/button.tsx': `export function Button() { return null; }`,
			'src/app/spread-controls.tsx': `
				import { Button } from '../components/ui/button.js';
				const staticStylingProps = { className: 'h-9 bg-primary', style: { borderColor: 'red' } };
				type AttributeOnlyProps = { readonly 'aria-label': string; readonly 'data-testid'?: string };
				type StylingProps = { readonly className?: string };
				export const View = (props: AttributeOnlyProps) => <Button {...props} />;
				export const StaticStyle = () => <Button {...staticStylingProps} />;
				export const UnknownStyle = (props: StylingProps) => <Button {...props} />;
			`,
		});

		expect(report.findings).toEqual(
			expect.arrayContaining([
				expect.objectContaining({
					ruleId: 'control-style-override',
					message: expect.stringContaining('h-9'),
				}),
				expect.objectContaining({
					ruleId: 'control-style-override',
					message: expect.stringContaining('bg-primary'),
				}),
				expect.objectContaining({
					ruleId: 'unknown-control-classes',
					message: expect.stringContaining('spread'),
				}),
				expect.objectContaining({ ruleId: 'raw-color' }),
			]),
		);
		expect(
			report.findings.filter(({ ruleId }) => ruleId === 'unknown-control-classes'),
		).toHaveLength(1);
	});

	test('proves Omit rest spreads exclude both styling properties and fails when style returns', async () => {
		const report = await checkFixture({
			'src/components/ui/button.tsx': `export function Button() { return null; }`,
			'src/app/typed-wrapper.tsx': `
				import { Button } from '../components/ui/button.js';
				type PrimitiveProps = { className?: string; style?: object; disabled?: boolean };
				interface SafeProps extends Omit<PrimitiveProps, 'className' | 'style'> { label: string }
				interface UnsafeProps extends Omit<PrimitiveProps, 'className'> { label: string }
				export function Safe(props: SafeProps) {
					const { label, ...attributes } = props; return <Button {...attributes}>{label}</Button>;
				}
				export function Unsafe(props: UnsafeProps) {
					const { label, ...attributes } = props; return <Button {...attributes}>{label}</Button>;
				}
			`,
		});

		expect(rulePaths(report, 'unknown-control-classes')).toEqual(['src/app/typed-wrapper.tsx']);
	});

	test('detects named CSS colors only in CSS and style contexts', async () => {
		const report = await checkFixture({
			'src/app/named-colors.css': `.message { color: rebeccapurple; }`,
			'src/app/named-colors.tsx': `
				export const ordinaryStatus = 'red';
				export const View = () => <section style={{ borderColor: 'aliceblue' }} />;
				export const options = { unsafeCSS: '.line { background: papayawhip; }' };
			`,
		});

		expect(rulePaths(report, 'raw-color')).toEqual([
			'src/app/named-colors.css',
			'src/app/named-colors.tsx',
			'src/app/named-colors.tsx',
		]);
	});

	test('classifies expression role controls and fails dynamic roles closed', async () => {
		const report = await checkFixture({
			'src/app/role-controls.tsx': `
				type DynamicRoleProps = { readonly role: string };
				export const MenuItem = () => <div role={'menuitem'} className="h-9 bg-primary" />;
				export const DynamicRole = (props: DynamicRoleProps) => <div role={props.role} />;
			`,
		});

		expect(report.findings).toEqual(
			expect.arrayContaining([
				expect.objectContaining({
					ruleId: 'control-style-override',
					message: expect.stringContaining('h-9'),
				}),
				expect.objectContaining({
					ruleId: 'control-style-override',
					message: expect.stringContaining('bg-primary'),
				}),
				expect.objectContaining({
					ruleId: 'unknown-control-classes',
					message: expect.stringContaining('role'),
				}),
			]),
		);
	});

	test('restricts direct palette imports and CSS variable reads to canonical homes and theme adapters', async () => {
		const report = await checkFixture({
			'src/app/bridge-viewer-tree-theme.ts': `
				import { bridgeDesignPalette } from '../design-tokens/bridge-design-palette.js';
				export const treeBackground = bridgeDesignPalette['--palette-canvas'];
			`,
			'src/review-viewer/code-view/bridge-code-view-theme.ts': `
				import { bridgeDesignPalette } from '../../design-tokens/bridge-design-palette.js';
				export const codeBackground = bridgeDesignPalette['--palette-canvas'];
			`,
			'src/app/unauthorized-theme.ts': `
				import { bridgeDesignPalette } from '../design-tokens/bridge-design-palette.js';
				export const background = bridgeDesignPalette['--palette-canvas'];
			`,
			'src/app/unauthorized.css': `.panel { color: var(--palette-primary); }`,
		});

		expect(rulePaths(report, 'palette-direct-read')).toEqual([
			'src/app/unauthorized-theme.ts',
			'src/app/unauthorized-theme.ts',
			'src/app/unauthorized.css',
		]);
	});

	test('rejects unlayered control font resets while accepting the base-layer reset', async () => {
		const report = await checkFixture(
			{},
			{
				cssSource: canonicalCss.replace(
					'@layer base { button, input, textarea { font: inherit; } }',
					'button, input, textarea { font: inherit; }',
				),
			},
		);

		expect(report.findings).toContainEqual(
			expect.objectContaining({ ruleId: 'unlayered-control-reset' }),
		);
	});

	test('sorts duplicated diagnostics and reports parse and read failures by deterministic path', async () => {
		const packageRootPath = await writeFixtureTree({
			'src/app/bridge-app.css': canonicalCss,
			'src/design-tokens/bridge-design-palette.ts': canonicalMirror,
			'src/app/z-broken.tsx': `export const Broken = <div`,
			'src/app/a-broken.css': `.broken { color:`,
		});
		await writeFileAt(packageRootPath, 'src/app/unreadable.ts', 'export const value = 1;');

		const report = await checkBridgeWebStyleSystem({ packageRootPath, readFile: readFixtureFile });

		expect(report.findings.map(({ relativePath }) => relativePath)).toEqual(
			report.findings.map(({ relativePath }) => relativePath).toSorted(),
		);
		expect(rulePaths(report, 'evaluation-failure')).toEqual([
			'src/app/a-broken.css',
			'src/app/unreadable.ts',
			'src/app/z-broken.tsx',
		]);
	});
});

async function checkFixture(
	files: Readonly<Record<string, string>>,
	overrides: { readonly cssSource?: string; readonly mirrorSource?: string } = {},
): Promise<StyleSystemReport> {
	const packageRootPath = await writeFixtureTree({
		'src/app/bridge-app.css': overrides.cssSource ?? canonicalCss,
		'src/design-tokens/bridge-design-palette.ts': overrides.mirrorSource ?? canonicalMirror,
		...files,
	});
	return checkBridgeWebStyleSystem({ packageRootPath });
}

async function writeFixtureTree(files: Readonly<Record<string, string>>): Promise<string> {
	const packageRootPath = await mkdtemp(join(tmpdir(), 'bridge-style-system-'));
	await Promise.all(
		Object.entries(files).map(async ([relativePath, sourceText]) => {
			await writeFileAt(packageRootPath, relativePath, sourceText);
		}),
	);
	return packageRootPath;
}

async function writeFileAt(
	rootPath: string,
	relativePath: string,
	sourceText: string,
): Promise<void> {
	const filePath = join(rootPath, relativePath);
	await mkdir(dirname(filePath), { recursive: true });
	await writeFile(filePath, sourceText);
}

function rulePaths(
	report: Awaited<ReturnType<typeof checkBridgeWebStyleSystem>>,
	ruleId: string,
): readonly string[] {
	return report.findings
		.filter((finding) => finding.ruleId === ruleId)
		.map(({ relativePath }) => relativePath);
}

void ({} satisfies CheckBridgeWebStyleSystemProps);

async function readFixtureFile(filePath: string): Promise<string> {
	if (filePath.endsWith('unreadable.ts')) {
		throw new Error('synthetic read failure');
	}
	return (await import('node:fs/promises')).readFile(filePath, 'utf8');
}
