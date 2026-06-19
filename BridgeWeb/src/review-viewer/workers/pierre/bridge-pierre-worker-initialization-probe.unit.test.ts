import { describe, expect, test, vi } from 'vitest';

import {
	runBridgePierreWorkerInitializationProbe,
	writeBridgePierreWorkerInitializationProbeSnapshotToDataset,
	type BridgePierreWorkerInitializationProbeDatasetTarget,
	type BridgePierreWorkerInitializationProbeSnapshot,
} from './bridge-pierre-worker-initialization-probe.js';

describe('Bridge Pierre worker initialization probe', () => {
	test('records theme and language resolution stages in order', async () => {
		const snapshots: BridgePierreWorkerInitializationProbeSnapshot[] = [];

		const finalSnapshot = await runBridgePierreWorkerInitializationProbe({
			themeNames: ['catppuccin-mocha'],
			languages: [],
			resolvers: {
				resolveThemes: async () => [{ name: 'catppuccin-mocha' }],
				resolveLanguages: async () => [],
			},
			onSnapshot: (snapshot): void => {
				snapshots.push(snapshot);
			},
		});

		expect(snapshots.map((snapshot) => snapshot.stage)).toEqual([
			'theme-resolution-started',
			'theme-resolution-resolved',
			'language-resolution-started',
			'language-resolution-resolved',
		]);
		expect(finalSnapshot).toEqual({
			stage: 'language-resolution-resolved',
			themeCount: 1,
			languageCount: 0,
			failureReason: '',
		});
	});

	test('stops at a theme resolution timeout', async () => {
		vi.useFakeTimers();
		const snapshots: BridgePierreWorkerInitializationProbeSnapshot[] = [];

		const probePromise = runBridgePierreWorkerInitializationProbe({
			themeNames: ['catppuccin-mocha'],
			languages: ['typescript'],
			timeoutMilliseconds: 25,
			resolvers: {
				resolveThemes: () => new Promise(() => undefined),
				resolveLanguages: async () => {
					throw new Error('should not resolve languages after theme timeout');
				},
			},
			onSnapshot: (snapshot): void => {
				snapshots.push(snapshot);
			},
		});
		await vi.advanceTimersByTimeAsync(25);
		const finalSnapshot = await probePromise;
		vi.useRealTimers();

		expect(snapshots.map((snapshot) => snapshot.stage)).toEqual([
			'theme-resolution-started',
			'theme-resolution-timed-out',
		]);
		expect(finalSnapshot).toEqual({
			stage: 'theme-resolution-timed-out',
			themeCount: 0,
			languageCount: 0,
			failureReason: 'timeout',
		});
	});

	test('records language resolution failures without exposing raw error text', async () => {
		const finalSnapshot = await runBridgePierreWorkerInitializationProbe({
			themeNames: ['catppuccin-mocha'],
			languages: ['typescript'],
			resolvers: {
				resolveThemes: async () => [{ name: 'catppuccin-mocha' }],
				resolveLanguages: async () => {
					throw new TypeError('private path /Users/example leaked through bundler');
				},
			},
		});

		expect(finalSnapshot).toEqual({
			stage: 'language-resolution-failed',
			themeCount: 1,
			languageCount: 0,
			failureReason: 'TypeError',
		});
	});

	test('writes snapshots directly to a dataset target', () => {
		const rootElement: BridgePierreWorkerInitializationProbeDatasetTarget = {
			dataset: {},
		};

		writeBridgePierreWorkerInitializationProbeSnapshotToDataset({
			rootElement,
			snapshot: {
				stage: 'theme-resolution-timed-out',
				themeCount: 0,
				languageCount: 0,
				failureReason: 'timeout',
			},
		});

		expect(rootElement.dataset).toEqual({
			bridgePierreWorkerPoolInitProbeStage: 'theme-resolution-timed-out',
			bridgePierreWorkerPoolInitProbeThemeCount: '0',
			bridgePierreWorkerPoolInitProbeLanguageCount: '0',
			bridgePierreWorkerPoolInitProbeFailureReason: 'timeout',
		});
	});
});
