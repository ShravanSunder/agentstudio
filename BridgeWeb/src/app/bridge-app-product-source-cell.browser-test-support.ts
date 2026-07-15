import { commands } from '@vitest/browser/context';
import { expect } from 'vitest';

import {
	bridgeProductSourceCellOracleSchema,
	bridgeProductSourceCellPaintReportSchema,
	type BridgeProductSourceCellSourceKind,
} from './bridge-app-product-source-cell-contract.js';

const sourceCellTestEntryByProject = {
	'VB-deterministic-fixture': 'src/app/bridge-app-product-deterministic-fixture.browser.test.tsx',
	'VB-real-worktree': 'src/app/bridge-app-product-real-worktree.browser.test.tsx',
} as const;

declare module '@vitest/browser/context' {
	interface BrowserCommands {
		bridgeInstallSourceCellNetworkProbe: () => Promise<void>;
		bridgeReadSourceCellNetworkFailures: () => Promise<readonly string[]>;
		bridgeWriteSourceCellReport: (report: unknown) => Promise<string>;
	}
}

export async function expectBridgeProductSourceCellCorrelation(props: {
	readonly expectedOracleKind: 'fixtureManifest' | 'gitObjectDatabase';
	readonly expectedProjectName: 'VB-deterministic-fixture' | 'VB-real-worktree';
	readonly expectedSourceKind: BridgeProductSourceCellSourceKind;
	readonly report?: unknown;
}): Promise<string> {
	const paintReport = bridgeProductSourceCellPaintReportSchema.parse(
		props.report ?? Reflect.get(globalThis, '__bridgeProductSourceCellReport'),
	);
	expect(paintReport.projectName).toBe(props.expectedProjectName);
	expect(paintReport.sourceKind).toBe(props.expectedSourceKind);
	expect(paintReport.paneSessionId).not.toBe(paintReport.workerInstanceId);
	expect(paintReport.testEntry).toBe(sourceCellTestEntryByProject[props.expectedProjectName]);

	const oracleResponse = await fetch(paintReport.oracleUrl, {
		cache: 'no-store',
		headers: { Accept: 'application/json' },
	});
	expect(oracleResponse.ok, 'independent source oracle must be reachable').toBe(true);
	const oracle = bridgeProductSourceCellOracleSchema.parse(await oracleResponse.json());
	expect(oracle.oracleKind).toBe(props.expectedOracleKind);
	expect(oracle.runMarker).toBe(paintReport.runMarker);
	expect(oracle.sourceChecksum).toBe(paintReport.sourceChecksum);
	expect(oracle.sourceKind).toBe(props.expectedSourceKind);

	const reviewPositions = new Set(
		paintReport.correlations
			.filter((correlation) => correlation.surface === 'review')
			.map((correlation) => correlation.position),
	);
	expect(
		[...reviewPositions].toSorted(),
		'Review proof must traverse readable early, middle, and final items',
	).toEqual(['early', 'final', 'middle']);
	expect(
		paintReport.correlations.some(
			(correlation) => correlation.surface === 'file' && correlation.position === 'final',
		),
		'File proof must reach readable final source content',
	).toBe(true);

	for (const correlation of paintReport.correlations) {
		const oracleEntry = oracle.entries.find(
			(entry) =>
				entry.surface === correlation.surface &&
				entry.itemId === correlation.itemId &&
				entry.role === correlation.role,
		);
		expect(
			oracleEntry,
			`missing independent oracle for ${correlation.surface}:${correlation.itemId}:${correlation.role}`,
		).toBeDefined();
		if (oracleEntry === undefined) continue;

		expect(correlation.semanticItemId).toBe(correlation.itemId);
		expect(correlation.readableDomItemId).toBe(correlation.itemId);
		expect(correlation.sourceIdentity).toBe(oracleEntry.sourceIdentity);
		expect(correlation.sourceGeneration).toBe(oracleEntry.sourceGeneration);
		expect(correlation.observedSha256).toBe(oracleEntry.sha256);
		expect(correlation.descriptorId).not.toBe(correlation.requestId);
		expect(correlation.contentRequestId).toBe(correlation.requestId);
		expect(correlation.disposition).toBe('painted');
		expect(correlation.readableText).toContain(oracleEntry.canaryText);
		if (correlation.selectionState === 'selected') {
			expect(correlation.selectedItemId).toBe(correlation.itemId);
		}
	}
	return await commands.bridgeWriteSourceCellReport(paintReport);
}
