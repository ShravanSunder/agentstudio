import { EventEmitter } from 'node:events';
import { join } from 'node:path';

import { describe, expect, test } from 'vitest';

import {
	bridgeDevelopmentServerSourceChangeIsRelevant,
	bridgeDevelopmentServerWatchedPaths,
	registerBridgeDevelopmentServerHttpCloseCleanup,
	registerBridgeDevelopmentServerProcessExitCleanup,
	requireOwnedBridgeDevelopmentServerExit,
} from './bridge-development-server-vite-plugin.ts';

describe('Bridge development server Vite shutdown boundary', () => {
	test('starts owned cleanup when the real HTTP server closes', async () => {
		// Arrange: process termination can close Vite's HTTP server before Rollup close hooks finish.
		const httpServer = new EventEmitter();
		let cleanupCallCount = 0;
		let resolveCleanupStarted: (() => void) | null = null;
		const cleanupStarted = new Promise<void>((resolve): void => {
			resolveCleanupStarted = resolve;
		});
		registerBridgeDevelopmentServerHttpCloseCleanup({
			httpServer,
			reportFailure: (): void => {},
			shutdown: async (): Promise<void> => {
				cleanupCallCount += 1;
				resolveCleanupStarted?.();
			},
		});

		// Act
		httpServer.emit('close');
		await cleanupStarted;

		// Assert
		expect(cleanupCallCount).toBe(1);
	});

	test('removes the isolated data root when Vite receives a termination signal', () => {
		// Arrange: pnpm Ctrl-C can end the process group before Vite awaits async close hooks.
		const processEmitter = new EventEmitter();
		const removedDataRoots: string[] = [];
		registerBridgeDevelopmentServerProcessExitCleanup({
			dataRootPath: '/tmp/agentstudio-bridge-vite-owned',
			processEmitter,
			removeDataRootSynchronously: (dataRootPath): void => {
				removedDataRoots.push(dataRootPath);
			},
		});

		// Act
		processEmitter.emit('SIGINT');

		// Assert
		expect(removedDataRoots).toEqual(['/tmp/agentstudio-bridge-vite-owned']);
	});
});

describe('Bridge development server Vite watch boundary', () => {
	test('admits the complete server dependency closure and build inputs', () => {
		// Removing one of these owners would leave edits invisible to the development loop.
		const repoRootPath = '/workspace/agent-studio';
		const relevantPaths = [
			'.mise.toml',
			'Package.swift',
			'Package.resolved',
			'Sources/AgentStudioBridgeDevelopmentServer/Main.swift',
			'Sources/AgentStudio/Features/Bridge/Runtime/BridgeHost.swift',
			'Sources/AgentStudio/Core/Models/Pane.swift',
			'Sources/AgentStudio/Infrastructure/UUIDv7.swift',
			'Sources/AgentStudio/SharedComponents/Control.swift',
			'Sources/AgentStudioProgrammaticControl/Command.swift',
			'scripts/build-bridge-development-server.sh',
			'scripts/swift-build-slot.sh',
			'scripts/vendor-worktree.sh',
		];

		for (const relativePath of relevantPaths) {
			expect(
				bridgeDevelopmentServerSourceChangeIsRelevant({
					changedPath: join(repoRootPath, relativePath),
					repoRootPath,
				}),
				relativePath,
			).toBe(true);
		}
	});

	test('rejects frontend, tests, build output, and unrelated app features', () => {
		// Broadening this boundary would make unrelated product work trigger expensive Swift builds.
		const repoRootPath = '/workspace/agent-studio';
		const irrelevantPaths = [
			'BridgeWeb/src/app.tsx',
			'Tests/AgentStudioBridgeDevelopmentServerTests/ServerTests.swift',
			'Sources/AgentStudio/Features/CodeViewer/CodeViewer.swift',
			'Sources/AgentStudio/App/AppDelegate.swift',
			'Sources/AgentStudio/Core/Models/README.md',
			'.build-agent-1/debug/backend',
			'tmp/backend-state.json',
		];

		for (const relativePath of irrelevantPaths) {
			expect(
				bridgeDevelopmentServerSourceChangeIsRelevant({
					changedPath: join(repoRootPath, relativePath),
					repoRootPath,
				}),
				relativePath,
			).toBe(false);
		}
	});

	test('registers only explicit source directories and exact build files', () => {
		// Watching the repository root or all Sources would defeat the bounded rebuild contract.
		const repoRootPath = '/workspace/agent-studio';

		expect(bridgeDevelopmentServerWatchedPaths(repoRootPath)).toEqual([
			join(repoRootPath, '.mise.toml'),
			join(repoRootPath, 'Package.swift'),
			join(repoRootPath, 'Package.resolved'),
			join(repoRootPath, 'Sources/AgentStudioBridgeDevelopmentServer'),
			join(repoRootPath, 'Sources/AgentStudio/Features/Bridge'),
			join(repoRootPath, 'Sources/AgentStudio/Core'),
			join(repoRootPath, 'Sources/AgentStudio/Infrastructure'),
			join(repoRootPath, 'Sources/AgentStudio/SharedComponents'),
			join(repoRootPath, 'Sources/AgentStudioProgrammaticControl'),
			join(repoRootPath, 'scripts/build-bridge-development-server.sh'),
			join(repoRootPath, 'scripts/swift-build-slot.sh'),
			join(repoRootPath, 'scripts/vendor-worktree.sh'),
		]);
	});

	test('rejects replacement when the owned backend remains alive after bounded shutdown', () => {
		// Launching anyway would race the surviving process for the configured proxy port.
		expect(() =>
			requireOwnedBridgeDevelopmentServerExit({
				exitCode: null,
				exitSignal: null,
				forcedTerminationRequired: true,
				ownedProcessAliveAfterStop: true,
			}),
		).toThrow(/remained alive/u);
		expect(() =>
			requireOwnedBridgeDevelopmentServerExit({
				exitCode: null,
				exitSignal: 'SIGTERM',
				forcedTerminationRequired: false,
				ownedProcessAliveAfterStop: false,
			}),
		).not.toThrow();
	});
});
