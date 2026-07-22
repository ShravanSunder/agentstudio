import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

describe('Bridge file viewer store source structure', () => {
	test('keeps File View off direct Zustand subscriptions after direct store removal', () => {
		const forbiddenTokens = [
			"from 'zustand",
			'from "zustand',
			'useStore(',
			'useStoreWithEqualityFn(',
			'createStore(',
			'createWithEqualityFn(',
			'subscribeWithSelector',
		];
		const violations = readFileViewerProductionSources().flatMap((entry): readonly string[] =>
			forbiddenTokens
				.filter((token): boolean => entry.source.includes(token))
				.map((token): string => `${entry.relativePath}: ${token}`),
		);

		expect(violations).toEqual([]);
	});

	test('keeps the File View UI store out of render snapshot ownership', () => {
		const storeSource = readSourceFile('file-viewer/state/bridge-file-viewer-store.ts');
		const forbiddenRenderSnapshotOwners = [
			'readonly renderState',
			'readonly openFileState',
			'readonly initialSurfaceLoadState',
			'readonly refreshDebugState',
			'readonly lastOpenLoadTelemetry',
			'readonly lastDemandDispatchDebugState',
			'setRenderState',
			'setOpenFileState',
			'setInitialSurfaceLoadState',
			'setRefreshDebugState',
			'setLastOpenLoadTelemetry',
			'setLastDemandDispatchDebugState',
		].filter((token): boolean => storeSource.includes(token));

		expect(forbiddenRenderSnapshotOwners).toEqual([]);
	});

	test('does not introduce a File View route-local render snapshot store', () => {
		const sources = readFileViewerProductionSources();
		const violations = sources.flatMap(({ relativePath, source }) =>
			['BridgeFileViewerRenderSnapshotStore', 'createBridgeFileViewerRenderSnapshotStore']
				.filter((token): boolean => source.includes(token))
				.map((token): string => `${relativePath}: ${token}`),
		);

		expect(violations).toEqual([]);
	});

	test('keeps File View product transport out of React surface props', () => {
		const appPropsSource = readSourceFile('file-viewer/bridge-file-viewer-app-props.ts');
		const bootstrapSource = readSourceFile('app/bridge-app-bootstrap.tsx');
		const devBootstrapSource = readSourceFile('app/bridge-app-dev-bootstrap.tsx');
		const modeSource = readSourceFile('app/bridge-app-file-viewer-mode.tsx');
		const appSource = readSourceFile('file-viewer/bridge-file-viewer-app.tsx');

		const propLevelTransportTokens = [
			'readonly fetchResource?:',
			'readonly loadInitialSurface?:',
			'readonly registerSurfaceStreamResetRequiredCallback?:',
			'readonly requestFileDescriptor?:',
			'readonly subscribeFrames?:',
		].filter((token): boolean => appPropsSource.includes(token));
		const explodedBootstrapTokens = [
			'nativeWorktreeFileBackend.fetchWorktreeFileResource',
			'nativeWorktreeFileBackend.loadWorktreeFileSurface',
			'nativeWorktreeFileBackend.registerWorktreeFileStreamResetRequiredCallback',
			'nativeWorktreeFileBackend.requestWorktreeFileDescriptor',
			'nativeWorktreeFileBackend.subscribeWorktreeFileFrames',
			'worktreeBackend.fetchWorktreeFileResource',
			'worktreeBackend.loadWorktreeFileSurface',
			'worktreeBackend.requestWorktreeFileDescriptor',
			'worktreeBackend.subscribeWorktreeFileFrames',
		].filter(
			(token): boolean => bootstrapSource.includes(token) || devBootstrapSource.includes(token),
		);
		const fileViewModeTokens = [
			'worktreeFileSurfaceTransport',
			'useBridgeFileViewerFrameControllerProps',
			'registerSurfaceStreamResetRequiredCallback',
		].filter((token): boolean => modeSource.includes(token));
		const migratedAppTransportMembers = [
			'fetchResource',
			'loadInitialSurface',
			'requestFileDescriptor',
			'subscribeFrames',
		];
		const appPropsDestructureMatch = /const\s*\{(?<body>[\s\S]*?)\}\s*=\s*props;/u.exec(appSource);
		const appPropsDestructureBody = appPropsDestructureMatch?.groups?.['body'] ?? '';
		const destructuredAppTransportTokens = migratedAppTransportMembers
			.filter((member): boolean => new RegExp(`\\b${member}\\b`, 'u').test(appPropsDestructureBody))
			.map((member): string => `props destructure: ${member}`);
		const directAppTransportTokens = migratedAppTransportMembers
			.map((member): string => `props.${member}`)
			.filter((token): boolean => appSource.includes(token));
		const appTransportTokens = [...destructuredAppTransportTokens, ...directAppTransportTokens];

		expect({
			appTransportTokens,
			explodedBootstrapTokens,
			fileViewModeTokens,
			propLevelTransportTokens,
		}).toEqual({
			appTransportTokens: [],
			explodedBootstrapTokens: [],
			fileViewModeTokens: [],
			propLevelTransportTokens: [],
		});
		expect(appPropsSource).not.toContain('worktreeFileSurfaceTransport');
		expect(bootstrapSource).not.toContain('createBridgeAppNativeWorktreeFileBackend');
	});

	test('keeps File View production content fetching behind the comm worker', () => {
		const forbiddenContentFetchTokens = [
			'fetchResource',
			'WorktreeFileSurfaceRuntimeFetchResourceProps',
			'WorktreeFileSurfaceRuntimeFetchedResource',
			'makeWorktreeFileSurfaceRuntimeFetchedResource',
			'loadBridgeTextResourceWithTiming',
			'defaultFetchWorktreeFileResource',
		];
		const violations = readFileViewerProductionSources().flatMap(({ relativePath, source }) =>
			forbiddenContentFetchTokens
				.filter((token): boolean => source.includes(token))
				.map((token): string => `${relativePath}: ${token}`),
		);

		expect(violations).toEqual([]);
	});
});

interface SourceFileEntry {
	readonly relativePath: string;
	readonly source: string;
}

function readFileViewerProductionSources(): readonly SourceFileEntry[] {
	const sourceDirectory = fileURLToPath(new URL('../', import.meta.url));
	const fileViewerSources = readSourceFilesInDirectory({
		absoluteDirectory: join(sourceDirectory, 'file-viewer'),
		relativeDirectory: 'file-viewer',
	});
	const appFileViewerSources = readSourceFilesInDirectory({
		absoluteDirectory: join(sourceDirectory, 'app'),
		relativeDirectory: 'app',
	}).filter((entry): boolean => entry.relativePath.includes('file-viewer'));
	return [...fileViewerSources, ...appFileViewerSources];
}

function readSourceFile(relativePath: string): string {
	const sourceDirectory = fileURLToPath(new URL('../', import.meta.url));
	return readFileSync(join(sourceDirectory, relativePath), 'utf8');
}

function readSourceFilesInDirectory(props: {
	readonly absoluteDirectory: string;
	readonly relativeDirectory: string;
}): readonly SourceFileEntry[] {
	return readdirSync(props.absoluteDirectory, { withFileTypes: true }).flatMap((entry) => {
		const relativePath =
			props.relativeDirectory.length === 0
				? entry.name
				: `${props.relativeDirectory}/${entry.name}`;
		const absolutePath = join(props.absoluteDirectory, entry.name);
		if (entry.isDirectory()) {
			return readSourceFilesInDirectory({
				absoluteDirectory: absolutePath,
				relativeDirectory: relativePath,
			});
		}
		if (
			!entry.isFile() ||
			(!entry.name.endsWith('.ts') && !entry.name.endsWith('.tsx')) ||
			entry.name.includes('.test.') ||
			entry.name.includes('.browser.') ||
			entry.name.includes('browser-test') ||
			relativePath.includes('/test-support/')
		) {
			return [];
		}
		return [
			{
				relativePath,
				source: readFileSync(absolutePath, 'utf8'),
			},
		];
	});
}
