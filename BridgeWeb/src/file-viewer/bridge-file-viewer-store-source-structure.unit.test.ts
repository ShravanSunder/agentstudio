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

	test('keeps native File View transport behind one typed boundary prop', () => {
		const appPropsSource = readSourceFile('file-viewer/bridge-file-viewer-app-props.ts');
		const bootstrapSource = readSourceFile('app/bridge-app-bootstrap.tsx');
		const devBootstrapSource = readSourceFile('app/bridge-app-dev-bootstrap.tsx');
		const modeSource = readSourceFile('app/bridge-app-file-viewer-mode.tsx');
		const frameControllerSource = readSourceFile('app/bridge-file-viewer-frame-controller.ts');
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
			'props.fileViewerProps?.registerSurfaceStreamResetRequiredCallback',
		].filter((token): boolean => modeSource.includes(token));
		const frameControllerTokens = [
			'fileViewerProps?.loadInitialSurface',
			'fileViewerProps?.subscribeFrames',
		].filter((token): boolean => frameControllerSource.includes(token));
		const appTransportTokens = ['props.requestFileDescriptor', 'fetchResource,'].filter(
			(token): boolean => appSource.includes(token),
		);

		expect({
			appTransportTokens,
			explodedBootstrapTokens,
			fileViewModeTokens,
			frameControllerTokens,
			propLevelTransportTokens,
		}).toEqual({
			appTransportTokens: [],
			explodedBootstrapTokens: [],
			fileViewModeTokens: [],
			frameControllerTokens: [],
			propLevelTransportTokens: [],
		});
		expect(appPropsSource).toContain('readonly worktreeFileSurfaceTransport?:');
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
			entry.name.includes('.browser.')
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
