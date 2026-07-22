import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

type HeadRecoveryDisposition = 'adapt' | 'preserve' | 'reject';

interface HeadRecoveryEntry {
	readonly disposition: HeadRecoveryDisposition;
	readonly path: string;
}

const headRecoveryEntries = [
	entry('reject', 'BridgeWeb/src/app/bridge-app-review-controller.ts'),
	entry('adapt', 'BridgeWeb/src/app/bridge-app-review-navigation-controller.ts'),
	entry('adapt', 'BridgeWeb/src/app/bridge-app-review-selection-controller.ts'),
	entry('adapt', 'BridgeWeb/src/app/bridge-app-review-viewer-shell-boundary.tsx'),
	entry('reject', 'BridgeWeb/src/review-viewer/projections/review-item-window-budget.ts'),
	entry('adapt', 'BridgeWeb/src/review-viewer/projections/review-item-window-budget.unit.test.ts'),
	entry('reject', 'BridgeWeb/src/review-viewer/projections/use-review-projection-coordinator.ts'),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/projections/use-review-projection-coordinator.unit.test.ts',
	),
	entry('reject', 'BridgeWeb/src/review-viewer/state/review-viewer-store.ts'),
	entry('adapt', 'BridgeWeb/src/review-viewer/state/review-viewer-store.unit.test.ts'),
	entry(
		'preserve',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-benchmark-workloads.ts',
	),
	entry(
		'preserve',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-benchmark-workloads.unit.test.ts',
	),
	entry('preserve', 'BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser-dom.ts'),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration-large.browser.test.tsx',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration-scroll.browser.test.tsx',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.browser-test-support.ts',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.browser.test.tsx',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.integration.test-support.ts',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.virtualizer.browser.test.tsx',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-browser.virtualizer.test-support.ts',
	),
	entry(
		'reject',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-markdown-worker-test-client.ts',
	),
	entry(
		'preserve',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend-retouch-fixtures.ts',
	),
	entry(
		'preserve',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend-support.ts',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.browser.test.ts',
	),
	entry('reject', 'BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.ts'),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer-render-slices.browser.test.tsx',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/test-support/bridge-viewer.browser.benchmark-support.tsx',
	),
	entry('adapt', 'BridgeWeb/src/review-viewer/test-support/bridge-viewer.browser.benchmark.tsx'),
	entry('preserve', 'BridgeWeb/src/review-viewer/test-support/review-viewer-fixtures.ts'),
	entry(
		'reject',
		'BridgeWeb/src/review-viewer/workers/projection/review-projection-sync-client.ts',
	),
	entry(
		'reject',
		'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-client.ts',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-client.unit.test.ts',
	),
	entry(
		'reject',
		'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-entry.ts',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-entry.unit.test.ts',
	),
	entry(
		'reject',
		'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-planner.ts',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-planner.unit.test.ts',
	),
	entry('reject', 'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-rpc.ts'),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-rpc.unit.test.ts',
	),
	entry(
		'reject',
		'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-transport.ts',
	),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-transport.unit.test.ts',
	),
	entry(
		'reject',
		'BridgeWeb/src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.test-support.ts',
	),
	entry('reject', 'BridgeWeb/src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.ts'),
	entry(
		'adapt',
		'BridgeWeb/src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.unit.test.ts',
	),
] as const satisfies readonly HeadRecoveryEntry[];

const rejectedRuntimePathsExpectedAbsent = [
	'BridgeWeb/src/app/bridge-app-review-controller.ts',
	'BridgeWeb/src/review-viewer/projections/use-review-projection-coordinator.ts',
	'BridgeWeb/src/review-viewer/state/review-viewer-store.ts',
	'BridgeWeb/src/review-viewer/test-support/bridge-viewer-markdown-worker-test-client.ts',
	'BridgeWeb/src/review-viewer/test-support/bridge-viewer-mocked-backend.ts',
	'BridgeWeb/src/review-viewer/workers/projection/review-projection-sync-client.ts',
	'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-client.ts',
	'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-entry.ts',
	'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-planner.ts',
	'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-rpc.ts',
	'BridgeWeb/src/review-viewer/workers/projection/review-projection-worker-transport.ts',
	'BridgeWeb/src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.test-support.ts',
	'BridgeWeb/src/review-viewer/workers/shared-rpc/bridge-comm-worker-transport.ts',
] as const;

const deferredScenarioTargetsByHeadPath = {
	'BridgeWeb/src/review-viewer/projections/review-item-window-budget.unit.test.ts':
		'BridgeWeb/src/core/comm-worker/bridge-worker-complete-item-admission-policy.unit.test.ts',
} as const satisfies Readonly<Record<string, string>>;

describe('Review HEAD recovery disposition', () => {
	test('represents every accepted Section 6 HEAD path exactly once', () => {
		const uniquePaths = new Set(headRecoveryEntries.map((recoveryEntry) => recoveryEntry.path));

		expect(headRecoveryEntries).toHaveLength(43);
		expect(uniquePaths.size).toBe(headRecoveryEntries.length);
		expect(entriesWithDisposition('adapt')).toHaveLength(23);
		expect(entriesWithDisposition('preserve')).toHaveLength(6);
		expect(entriesWithDisposition('reject')).toHaveLength(14);
	});

	test('keeps rejected runtime owners absent', () => {
		const presentRejectedRuntimePaths = rejectedRuntimePathsExpectedAbsent.filter(
			(relativePath): boolean => sourceFileExists(relativePath),
		);

		expect(presentRejectedRuntimePaths).toEqual([]);
	});

	test('keeps the rejected legacy window budget absent while S4a owns replacement proof', () => {
		const productionImporters = productionTypeScriptPaths().filter((relativePath): boolean =>
			readSource(relativePath).includes('review-item-window-budget'),
		);

		expect(productionImporters).toEqual([]);
		expect(
			sourceFileExists('BridgeWeb/src/review-viewer/projections/review-item-window-budget.ts'),
		).toBe(false);
		expect(
			sourceFileExists(
				'BridgeWeb/src/review-viewer/projections/review-item-window-budget.unit.test.ts',
			),
		).toBe(false);
		expect(
			deferredScenarioTargetsByHeadPath[
				'BridgeWeb/src/review-viewer/projections/review-item-window-budget.unit.test.ts'
			],
		).toBe(
			'BridgeWeb/src/core/comm-worker/bridge-worker-complete-item-admission-policy.unit.test.ts',
		);
	});
});

function entry(disposition: HeadRecoveryDisposition, path: string): HeadRecoveryEntry {
	return { disposition, path };
}

function entriesWithDisposition(
	disposition: HeadRecoveryDisposition,
): readonly HeadRecoveryEntry[] {
	return headRecoveryEntries.filter(
		(recoveryEntry): boolean => recoveryEntry.disposition === disposition,
	);
}

function sourceFileExists(relativePath: string): boolean {
	return existsSync(fileURLToPath(new URL(`../../../../${relativePath}`, import.meta.url)));
}

function readSource(relativePath: string): string {
	return readFileSync(
		fileURLToPath(new URL(`../../../../${relativePath}`, import.meta.url)),
		'utf8',
	);
}

function productionTypeScriptPaths(): readonly string[] {
	return readProductionTypeScriptPaths(
		fileURLToPath(new URL('../../', import.meta.url)),
		'BridgeWeb/src',
	);
}

function readProductionTypeScriptPaths(
	absoluteDirectoryPath: string,
	relativeDirectoryPath: string,
): readonly string[] {
	return readdirSync(absoluteDirectoryPath, { withFileTypes: true }).flatMap((directoryEntry) => {
		const absolutePath = join(absoluteDirectoryPath, directoryEntry.name);
		const relativePath = join(relativeDirectoryPath, directoryEntry.name);
		if (directoryEntry.isDirectory()) {
			if (directoryEntry.name === 'test-support') return [];
			return readProductionTypeScriptPaths(absolutePath, relativePath);
		}
		if (
			!directoryEntry.isFile() ||
			(!directoryEntry.name.endsWith('.ts') && !directoryEntry.name.endsWith('.tsx')) ||
			directoryEntry.name.includes('.test.')
		) {
			return [];
		}
		return [relativePath];
	});
}
