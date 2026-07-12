import type { Dirent } from 'node:fs';
import { readdir, readFile } from 'node:fs/promises';
import { dirname, extname, join, relative } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import ts from 'typescript';

type RuleId =
	| 'max-file-lines'
	| 'no-private-pierre-imports'
	| 'pierre-codeview-import-boundary'
	| 'pierre-trees-import-boundary'
	| 'pierre-worker-import-boundary'
	| 'markdown-render-worker-boundary'
	| 'review-viewer-folder-boundary'
	| 'review-viewer-state-has-effects'
	| 'review-viewer-shell-has-content-effects'
	| 'telemetry-boundary'
	| 'worker-boundary'
	| 'no-raw-file-bodies-in-state'
	| 'core-imports-app-protocol'
	| 'dev-product-route-boundary'
	| 'worktree-dev-review-package-scaffolding';

export interface ArchitectureViolation {
	readonly ruleId: RuleId;
	readonly relativePath: string;
	readonly line: number;
	readonly column: number;
	readonly message: string;
}

export interface ArchitectureReport {
	readonly ok: boolean;
	readonly violations: readonly ArchitectureViolation[];
}

export interface CheckBridgeWebArchitectureProps {
	readonly packageRootPath?: string;
}

interface SourceContext {
	readonly relativePath: string;
	readonly sourceFile: ts.SourceFile;
	readonly sourceText: string;
	readonly violations: ArchitectureViolation[];
}

interface CheckSourceFileProps {
	readonly filePath: string;
	readonly packageRootPath: string;
}

interface AddViolationProps {
	readonly ruleId: RuleId;
	readonly node?: ts.Node;
	readonly position?: number;
	readonly message: string;
}

const defaultPackageRootPath = fileURLToPath(new URL('../', import.meta.url));
const checkedExtensions = new Set(['.ts', '.tsx']);
const ignoredDirectoryNames = new Set(['node_modules', 'dist', 'coverage', '.vite']);
const maxSourceFileLineCount = 1000;
const allowedPostMessagePaths = new Set([
	'src/app/diagnostics/bridge-product-stream-webkit-feasibility-probe.ts',
	'src/app/diagnostics/bridge-worker-fetch-probe-worker-entry.ts',
	'src/core/comm-worker/bridge-comm-worker-client.ts',
	'src/core/comm-worker/bridge-comm-worker-entry.ts',
	'src/core/comm-worker/bridge-pane-comm-worker-session.ts',
	'src/core/comm-worker/bridge-comm-worker-runtime-protocol.ts',
	'src/core/comm-worker/bridge-product-session-contracts.ts',
	'src/file-viewer/bridge-file-viewer-browser-test-comm-worker.ts',
]);
const publicPierreExports = new Set([
	'@pierre/diffs',
	'@pierre/diffs/react',
	'@pierre/diffs/ssr',
	'@pierre/diffs/worker',
	'@pierre/diffs/worker/worker.js',
	'@pierre/diffs/worker/worker-portable.js',
	'@pierre/theming/themes',
	'@pierre/trees',
	'@pierre/trees/react',
	'@pierre/trees/ssr',
	'@pierre/trees/web-components',
]);

export async function checkBridgeWebArchitecture(
	props: CheckBridgeWebArchitectureProps = {},
): Promise<ArchitectureReport> {
	const packageRootPath = props.packageRootPath ?? defaultPackageRootPath;
	const sourceFilePaths = await collectSourceFiles(packageRootPath);
	const violationGroups = await Promise.all(
		sourceFilePaths.map(
			(filePath: string): Promise<readonly ArchitectureViolation[]> =>
				checkSourceFile({ filePath, packageRootPath }),
		),
	);
	const violations = violationGroups.flat().toSorted(compareViolations);

	return {
		ok: violations.length === 0,
		violations,
	};
}

async function collectSourceFiles(directoryPath: string): Promise<readonly string[]> {
	let entries: readonly Dirent[];

	try {
		entries = await readdir(directoryPath, { withFileTypes: true });
	} catch (error: unknown) {
		if (isNodeErrorWithCode(error, 'ENOENT')) {
			return [];
		}

		throw error;
	}

	const entryGroups = await Promise.all(
		entries.map(async (entry: Dirent): Promise<readonly string[]> => {
			const entryPath = join(directoryPath, entry.name);

			if (entry.isDirectory()) {
				if (ignoredDirectoryNames.has(entry.name)) {
					return [];
				}
				return collectSourceFiles(entryPath);
			}

			if (entry.isFile() && checkedExtensions.has(extname(entry.name))) {
				return [entryPath];
			}

			return [];
		}),
	);

	return entryGroups.flat();
}

async function checkSourceFile(
	props: CheckSourceFileProps,
): Promise<readonly ArchitectureViolation[]> {
	const sourceText = await readFile(props.filePath, 'utf8');
	const relativePath = normalizePath(relative(props.packageRootPath, props.filePath));
	const sourceFile = ts.createSourceFile(
		props.filePath,
		sourceText,
		ts.ScriptTarget.Latest,
		true,
		scriptKindForPath(props.filePath),
	);
	const context: SourceContext = {
		relativePath,
		sourceFile,
		sourceText,
		violations: [],
	};

	checkMaxSourceFileLineCount(context);
	checkReviewViewerFolderBoundary(context);
	walkSourceFile(sourceFile, (node: ts.Node): void => {
		checkImportSource(context, node);
		checkWorkerUsage(context, node);
		checkStateEffects(context, node);
		checkTelemetryEmit(context, node);
	});
	checkRawBodyStateFields(context);
	checkWorktreeDevReviewPackageScaffolding(context);

	return context.violations;
}

function checkMaxSourceFileLineCount(context: SourceContext): void {
	const lineCount = sourceLineCount(context.sourceText);
	if (lineCount <= maxSourceFileLineCount) {
		return;
	}

	addViolation(context, {
		ruleId: 'max-file-lines',
		message: `BridgeWeb TypeScript source files must be ${maxSourceFileLineCount} lines or fewer; split this file by controller, store, hook, runtime, test-support, or visual shell responsibility. Found ${lineCount} lines.`,
	});
}

function sourceLineCount(sourceText: string): number {
	if (sourceText.length === 0) {
		return 0;
	}

	const normalizedSourceText = sourceText.replace(/\r\n?/gu, '\n');
	const trimmedTrailingNewlineSourceText = normalizedSourceText.endsWith('\n')
		? normalizedSourceText.slice(0, -1)
		: normalizedSourceText;
	return trimmedTrailingNewlineSourceText.split('\n').length;
}

function walkSourceFile(node: ts.Node, visitNode: (node: ts.Node) => void): void {
	visitNode(node);
	node.forEachChild((childNode: ts.Node): void => walkSourceFile(childNode, visitNode));
}

function checkPierreImportSource(
	context: SourceContext,
	node: ts.Node,
	rawImportSource: string,
	importSource: string,
): void {
	if (isArchitectureCheckerPath(context.relativePath)) {
		return;
	}

	if (importSource.startsWith('@pierre/') && !publicPierreExports.has(importSource)) {
		addViolation(context, {
			ruleId: 'no-private-pierre-imports',
			node,
			message: `Pierre import must use a public package export: ${rawImportSource}`,
		});
		return;
	}

	if (isPrivatePierrePath(rawImportSource)) {
		addViolation(context, {
			ruleId: 'no-private-pierre-imports',
			node,
			message: `Pierre import must not reference private package paths: ${rawImportSource}`,
		});
	}
}

function checkImportSource(context: SourceContext, node: ts.Node): void {
	const rawImportSource = readImportSource(node);

	if (rawImportSource === null) {
		return;
	}

	const importSource = normalizeImportSpecifier(rawImportSource);
	checkPierreImportSource(context, node, rawImportSource, importSource);
	if (
		!isTestPath(context.relativePath) &&
		context.relativePath !== 'vite.config.ts' &&
		(resolveImportTargetPath(context.relativePath, importSource) ?? importSource).includes(
			'bridge-product-dev-routes',
		)
	) {
		addViolation(context, {
			ruleId: 'dev-product-route-boundary',
			node,
			message:
				'production modules must not import the Vite-only Bridge product route module; Vite selects it at build time',
		});
	}

	if (isTestPath(context.relativePath)) {
		return;
	}

	if (isCorePath(context.relativePath) && isAppProtocolOrViewerImport(context, importSource)) {
		addViolation(context, {
			ruleId: 'core-imports-app-protocol',
			node,
			message: `generic core modules must not import app protocol or viewer modules: ${importSource}`,
		});
	}

	if (importSource.startsWith('@pierre/trees') && !isAllowedTreesImportPath(context.relativePath)) {
		addViolation(context, {
			ruleId: 'pierre-trees-import-boundary',
			node,
			message: `Pierre Trees runtime imports belong under owning viewer tree panes: ${importSource}`,
		});
	}

	if (isCodeViewImport(importSource) && !isAllowedCodeViewImportPath(context.relativePath)) {
		addViolation(context, {
			ruleId: 'pierre-codeview-import-boundary',
			node,
			message: `Pierre CodeView runtime imports belong under owning viewer code panes: ${importSource}`,
		});
	}

	if (
		isPierreWorkerImport(importSource) &&
		!isAllowedPierreWorkerImportPath(context.relativePath)
	) {
		addViolation(context, {
			ruleId: 'pierre-worker-import-boundary',
			node,
			message: `Pierre worker imports belong under review-viewer/workers/pierre: ${importSource}`,
		});
	}

	if (isStatePath(context.relativePath) && isStateEffectImport(importSource)) {
		addViolation(context, {
			ruleId: 'review-viewer-state-has-effects',
			node,
			message: `review-viewer/state must not import effectful boundary: ${importSource}`,
		});
	}

	if (
		isMarkdownRenderImport(importSource) &&
		!isAllowedMarkdownRenderImportPath(context.relativePath)
	) {
		addViolation(context, {
			ruleId: 'markdown-render-worker-boundary',
			node,
			message: `Markdown and Shiki rendering imports belong in the markdown worker renderer only: ${importSource}`,
		});
	}

	if (isShellPath(context.relativePath) && isContentEffectImport(importSource)) {
		addViolation(context, {
			ruleId: 'review-viewer-shell-has-content-effects',
			node,
			message: `review-viewer/shell must not import content loading boundary: ${importSource}`,
		});
	}
}

function checkWorkerUsage(context: SourceContext, node: ts.Node): void {
	if (isTestPath(context.relativePath)) {
		return;
	}

	if (
		!isAllowedWorkerConstructionPath(context.relativePath) &&
		ts.isNewExpression(node) &&
		ts.isIdentifier(node.expression) &&
		node.expression.text === 'Worker'
	) {
		addViolation(context, {
			ruleId: 'worker-boundary',
			node,
			message:
				'Worker construction belongs under review-viewer/workers/projection, workers/pierre, workers/markdown, or workers/shared-rpc',
		});
	}

	if (
		!isAllowedPostMessagePath(context.relativePath) &&
		ts.isCallExpression(node) &&
		ts.isPropertyAccessExpression(node.expression) &&
		node.expression.name.text === 'postMessage'
	) {
		addViolation(context, {
			ruleId: 'worker-boundary',
			node,
			message:
				'postMessage usage belongs to an owned worker lane, exact comm-worker gateway, or exact packaged diagnostic boundary',
		});
	}
}

function checkReviewViewerFolderBoundary(context: SourceContext): void {
	if (isTestPath(context.relativePath)) {
		return;
	}

	if (isPathInside(context.relativePath, 'src/review-viewer/runtime/')) {
		addViolation(context, {
			ruleId: 'review-viewer-folder-boundary',
			message:
				'review-viewer/runtime is too vague; move files to a feature-owned folder such as content or projections',
		});
		return;
	}

	if (isPathInside(context.relativePath, 'src/review-viewer/workers/rpc/')) {
		addViolation(context, {
			ruleId: 'review-viewer-folder-boundary',
			message:
				'review-viewer/workers/rpc is too vague; use workers/projection for projection workers or workers/shared-rpc for generic transport helpers',
		});
	}
}

function checkStateEffects(context: SourceContext, node: ts.Node): void {
	if (!isStatePath(context.relativePath)) {
		return;
	}

	if (
		ts.isCallExpression(node) &&
		ts.isIdentifier(node.expression) &&
		node.expression.text === 'fetch'
	) {
		addViolation(context, {
			ruleId: 'review-viewer-state-has-effects',
			node,
			message: 'state modules must not fetch content directly',
		});
	}

	if (!isStringLiteralLike(node)) {
		return;
	}

	if (
		node.text === 'system.bridgeTelemetry' ||
		node.text.startsWith('agentstudio://resource/') ||
		node.text.startsWith('agentstudio://app/')
	) {
		addViolation(context, {
			ruleId: 'review-viewer-state-has-effects',
			node,
			message: `state modules must not own Bridge transport strings: ${node.text}`,
		});
	}
}

function checkTelemetryEmit(context: SourceContext, node: ts.Node): void {
	if (
		!context.relativePath.startsWith('src/review-viewer/') ||
		isPathInside(context.relativePath, 'src/foundation/telemetry/') ||
		isTestPath(context.relativePath)
	) {
		return;
	}

	if (
		ts.isCallExpression(node) &&
		ts.isPropertyAccessExpression(node.expression) &&
		(node.expression.name.text === 'record' || node.expression.name.text === 'flush') &&
		node.expression.expression.getText(context.sourceFile).includes('telemetry')
	) {
		addViolation(context, {
			ruleId: 'telemetry-boundary',
			node,
			message: 'review-viewer code must route telemetry through foundation/telemetry adapters',
		});
	}
}

function checkRawBodyStateFields(context: SourceContext): void {
	if (!isStatePath(context.relativePath)) {
		return;
	}

	const match =
		/\b(?:loadedFileBody|rawFileBody|fileBody|bodyText|fileText|sourceText|contentText|selectedContentText|contentPromise|bodyPromise|abortController|workerHandle|pierreInstance)\b/u.exec(
			context.sourceText,
		);

	if (match === null) {
		return;
	}

	addViolation(context, {
		ruleId: 'no-raw-file-bodies-in-state',
		position: match.index,
		message:
			'state modules must store refs/status/facts, not raw bodies, promises, controllers, workers, or Pierre instances',
	});
}

function checkWorktreeDevReviewPackageScaffolding(context: SourceContext): void {
	if (!isWorktreeDevPath(context.relativePath) || isTestPath(context.relativePath)) {
		return;
	}

	const forbiddenPattern =
		context.relativePath === 'src/app/bridge-app-dev-bootstrap.tsx'
			? /\/__bridge-worktree\/(?:package|content)\b/u
			: /\b(?:loadReviewPackage|pushPackage|BridgeReviewPackage|bridgeReviewPackageSchema|buildReviewSnapshotFrame|dispatchBridgeDevHostAdmittedEnvelope)\b|\/__bridge-worktree\/(?:package|content)\b|foundation\/review-package/u;
	const match = forbiddenPattern.exec(context.sourceText);

	if (match === null) {
		return;
	}

	addViolation(context, {
		ruleId: 'worktree-dev-review-package-scaffolding',
		position: match.index,
		message:
			'Worktree dev route must use Worktree/File frames and descriptor content, not Review-package scaffolding',
	});
}

function readImportSource(node: ts.Node): string | null {
	if (
		(ts.isImportDeclaration(node) || ts.isExportDeclaration(node)) &&
		node.moduleSpecifier !== undefined &&
		isStringLiteralLike(node.moduleSpecifier)
	) {
		return node.moduleSpecifier.text;
	}

	if (!ts.isCallExpression(node) || node.arguments.length !== 1) {
		return null;
	}

	const firstArgument = node.arguments[0];

	if (firstArgument === undefined || !isStringLiteralLike(firstArgument)) {
		return null;
	}

	if (node.expression.kind === ts.SyntaxKind.ImportKeyword) {
		return firstArgument.text;
	}

	if (ts.isIdentifier(node.expression) && node.expression.text === 'require') {
		return firstArgument.text;
	}

	return null;
}

function isStringLiteralLike(
	node: ts.Node,
): node is ts.StringLiteral | ts.NoSubstitutionTemplateLiteral {
	return ts.isStringLiteral(node) || node.kind === ts.SyntaxKind.NoSubstitutionTemplateLiteral;
}

function isPrivatePierrePath(text: string): boolean {
	return (
		text.includes('@pierre/diffs/dist/') ||
		text.includes('@pierre/trees/dist/') ||
		text.includes('/packages/diffs/') ||
		text.includes('/packages/trees/') ||
		text.includes('pierrecomputer/pierre') ||
		text.includes('/libs-react/pierre/')
	);
}

function normalizeImportSpecifier(text: string): string {
	const queryIndex = text.search(/[?#]/);
	return queryIndex === -1 ? text : text.slice(0, queryIndex);
}

function isCodeViewImport(importSource: string): boolean {
	return importSource === '@pierre/diffs' || importSource === '@pierre/diffs/react';
}

function isPierreWorkerImport(importSource: string): boolean {
	return (
		importSource === '@pierre/diffs/worker' ||
		importSource === '@pierre/diffs/worker/worker.js' ||
		importSource === '@pierre/diffs/worker/worker-portable.js'
	);
}

function isAllowedTreesImportPath(relativePath: string): boolean {
	return (
		relativePath === 'src/app/bridge-viewer-tree-theme.ts' ||
		isPathInside(relativePath, 'src/file-viewer/') ||
		isPathInside(relativePath, 'src/review-viewer/trees/')
	);
}

function isAllowedCodeViewImportPath(relativePath: string): boolean {
	return (
		relativePath === 'src/core/comm-worker/bridge-worker-review-pierre-job-planner.ts' ||
		isPathInside(relativePath, 'src/file-viewer/') ||
		isPathInside(relativePath, 'src/review-viewer/code-view/') ||
		isPathInside(relativePath, 'src/review-viewer/workers/pierre/')
	);
}

function isAllowedPierreWorkerImportPath(relativePath: string): boolean {
	return isPathInside(relativePath, 'src/review-viewer/workers/pierre/');
}

function isAllowedWorkerConstructionPath(relativePath: string): boolean {
	return (
		relativePath === 'src/core/comm-worker/bridge-pane-comm-worker-session.ts' ||
		isPathInside(relativePath, 'src/core/telemetry-worker/') ||
		isPathInside(relativePath, 'src/review-viewer/workers/projection/') ||
		isPathInside(relativePath, 'src/review-viewer/workers/pierre/') ||
		isPathInside(relativePath, 'src/review-viewer/workers/markdown/') ||
		isPathInside(relativePath, 'src/review-viewer/workers/shared-rpc/')
	);
}

function isAllowedPostMessagePath(relativePath: string): boolean {
	return isAllowedWorkerConstructionPath(relativePath) || allowedPostMessagePaths.has(relativePath);
}

function isMarkdownRenderImport(importSource: string): boolean {
	return (
		importSource === '@shikijs/markdown-exit' ||
		importSource.startsWith('@shikijs/markdown-exit/') ||
		importSource === 'markdown-exit' ||
		importSource.startsWith('markdown-exit/') ||
		importSource === 'shiki' ||
		importSource.startsWith('shiki/')
	);
}

function isAllowedMarkdownRenderImportPath(relativePath: string): boolean {
	return (
		relativePath === 'src/review-viewer/workers/pierre/bridge-pierre-language-normalization.ts' ||
		relativePath === 'src/review-viewer/workers/markdown/bridge-markdown-render-worker-renderer.ts'
	);
}

function isStateEffectImport(importSource: string): boolean {
	return (
		importSource.startsWith('@pierre/') ||
		importSource.includes('/bridge/') ||
		importSource.includes('bridge-rpc') ||
		importSource.includes('bridge-resource-url') ||
		importSource.includes('/foundation/content') ||
		importSource.includes('/foundation/telemetry') ||
		importSource.includes('/review-viewer/workers') ||
		importSource.includes('../workers') ||
		importSource.includes('./workers')
	);
}

function isAppProtocolOrViewerImport(context: SourceContext, importSource: string): boolean {
	const targetPath = resolveImportTargetPath(context.relativePath, importSource) ?? importSource;
	return (
		isPathInside(targetPath, 'src/features/review/') ||
		isPathInside(targetPath, 'src/features/worktree-file/') ||
		isPathInside(targetPath, 'src/review-viewer/') ||
		isPathInside(targetPath, 'src/foundation/review-package/')
	);
}

function resolveImportTargetPath(relativePath: string, importSource: string): string | null {
	if (importSource.startsWith('@/')) {
		return normalizePath(join('src', importSource.slice(2)));
	}
	if (!importSource.startsWith('.')) {
		return null;
	}
	return normalizePath(join(dirname(relativePath), importSource));
}

function isCorePath(relativePath: string): boolean {
	return isPathInside(relativePath, 'src/core/');
}

function isWorktreeDevPath(relativePath: string): boolean {
	return (
		relativePath === 'src/app/bridge-app-dev-bootstrap.tsx' ||
		relativePath === 'scripts/dev-server/bridge-worktree-dev-provider.ts' ||
		relativePath === 'vite.config.ts'
	);
}

function isContentEffectImport(importSource: string): boolean {
	return importSource.includes('/foundation/content');
}

function isStatePath(relativePath: string): boolean {
	return (
		isPathInside(relativePath, 'src/review-viewer/state/') ||
		isPathInside(relativePath, 'src/features/review/state/') ||
		isPathInside(relativePath, 'src/features/worktree-file/state/')
	);
}

function isShellPath(relativePath: string): boolean {
	return isPathInside(relativePath, 'src/review-viewer/shell/');
}

function isTestPath(relativePath: string): boolean {
	return (
		/\.(?:unit|integration|e2e|browser)\.test\.[cm]?[jt]sx?$/u.test(relativePath) ||
		/\.browser\.[a-z0-9-]+-suite\.[cm]?[jt]sx?$/u.test(relativePath) ||
		/\.browser\.benchmark\.[cm]?[jt]sx?$/u.test(relativePath) ||
		relativePath.includes('/test-fixtures/')
	);
}

function isArchitectureCheckerPath(relativePath: string): boolean {
	return relativePath.startsWith('scripts/check-bridgeweb-architecture');
}

function scriptKindForPath(filePath: string): ts.ScriptKind {
	if (filePath.endsWith('.tsx')) {
		return ts.ScriptKind.TSX;
	}

	if (filePath.endsWith('.jsx')) {
		return ts.ScriptKind.JSX;
	}

	return ts.ScriptKind.TS;
}

function isPathInside(relativePath: string, directoryPath: string): boolean {
	return relativePath.startsWith(directoryPath);
}

function normalizePath(path: string): string {
	return path.replaceAll('\\', '/');
}

function addViolation(context: SourceContext, props: AddViolationProps): void {
	const violationPosition = props.position ?? props.node?.getStart(context.sourceFile) ?? 0;
	const lineAndCharacter = context.sourceFile.getLineAndCharacterOfPosition(violationPosition);

	context.violations.push({
		ruleId: props.ruleId,
		relativePath: context.relativePath,
		line: lineAndCharacter.line + 1,
		column: lineAndCharacter.character + 1,
		message: props.message,
	});
}

function compareViolations(left: ArchitectureViolation, right: ArchitectureViolation): number {
	return (
		left.relativePath.localeCompare(right.relativePath) ||
		left.line - right.line ||
		left.column - right.column ||
		left.ruleId.localeCompare(right.ruleId)
	);
}

function isNodeErrorWithCode(error: unknown, code: string): error is NodeJS.ErrnoException {
	return error instanceof Error && 'code' in error && error.code === code;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
	const report = await checkBridgeWebArchitecture();

	if (!report.ok) {
		for (const violation of report.violations) {
			console.error(
				[
					violation.relativePath,
					`${violation.line}:${violation.column}`,
					violation.ruleId,
					violation.message,
				].join(' - '),
			);
		}

		process.exitCode = 1;
	}
}
