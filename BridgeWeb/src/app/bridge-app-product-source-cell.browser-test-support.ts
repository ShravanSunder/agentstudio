import { expect } from 'vitest';
import { z } from 'zod';

const sourceCellKindSchema = z.enum(['deterministicFixture', 'liveGitWorktree']);
const sourceCellSurfaceSchema = z.enum(['file', 'review']);
const sourceCellTraversalPositionSchema = z.enum(['early', 'middle', 'final']);

const sourceCellPaintCorrelationSchema = z
	.object({
		descriptorId: z.string().min(1),
		disposition: z.literal('painted'),
		itemId: z.string().min(1),
		observedSha256: z.string().regex(/^[a-f0-9]{64}$/u),
		position: sourceCellTraversalPositionSchema,
		readableDomSelector: z.string().min(1),
		requestId: z.string().min(1),
		role: z.string().min(1),
		semanticItemId: z.string().min(1),
		sourceGeneration: z.number().int().nonnegative(),
		sourceIdentity: z.string().min(1),
		surface: sourceCellSurfaceSchema,
	})
	.strict();

const sourceCellPaintReportSchema = z
	.object({
		bundledPierreVersion: z.string().min(1),
		correlations: z.array(sourceCellPaintCorrelationSchema).min(4),
		oracleUrl: z.string().min(1),
		paneSessionId: z.string().min(1),
		projectName: z.enum(['VB-deterministic-fixture', 'VB-real-worktree']),
		runMarker: z.string().min(1),
		sourceKind: sourceCellKindSchema,
		workerInstanceId: z.string().min(1),
	})
	.strict();

const sourceCellOracleEntrySchema = z
	.object({
		canaryText: z.string().min(1),
		itemId: z.string().min(1),
		role: z.string().min(1),
		sha256: z.string().regex(/^[a-f0-9]{64}$/u),
		sourceGeneration: z.number().int().nonnegative(),
		sourceIdentity: z.string().min(1),
		surface: sourceCellSurfaceSchema,
	})
	.strict();

const sourceCellOracleSchema = z
	.object({
		entries: z.array(sourceCellOracleEntrySchema).min(4),
		oracleKind: z.enum(['fixtureManifest', 'gitObjectDatabase']),
		runMarker: z.string().min(1),
		sourceKind: sourceCellKindSchema,
	})
	.strict();

type SourceCellKind = z.infer<typeof sourceCellKindSchema>;

export async function expectBridgeProductSourceCellCorrelation(props: {
	readonly expectedOracleKind: 'fixtureManifest' | 'gitObjectDatabase';
	readonly expectedProjectName: 'VB-deterministic-fixture' | 'VB-real-worktree';
	readonly expectedSourceKind: SourceCellKind;
}): Promise<void> {
	const paintReport = sourceCellPaintReportSchema.parse(
		(globalThis as { readonly __bridgeProductSourceCellReport?: unknown })
			.__bridgeProductSourceCellReport,
	);
	expect(paintReport.projectName).toBe(props.expectedProjectName);
	expect(paintReport.sourceKind).toBe(props.expectedSourceKind);
	expect(paintReport.paneSessionId).not.toBe(paintReport.workerInstanceId);

	const oracleResponse = await fetch(paintReport.oracleUrl, {
		cache: 'no-store',
		headers: { Accept: 'application/json' },
	});
	expect(oracleResponse.ok, 'independent source oracle must be reachable').toBe(true);
	const oracle = sourceCellOracleSchema.parse(await oracleResponse.json());
	expect(oracle.oracleKind).toBe(props.expectedOracleKind);
	expect(oracle.runMarker).toBe(paintReport.runMarker);
	expect(oracle.sourceKind).toBe(props.expectedSourceKind);

	const reviewPositions = new Set(
		paintReport.correlations
			.filter((correlation) => correlation.surface === 'review')
			.map((correlation) => correlation.position),
	);
	expect(
		[...reviewPositions].sort(),
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
		expect(correlation.sourceIdentity).toBe(oracleEntry.sourceIdentity);
		expect(correlation.sourceGeneration).toBe(oracleEntry.sourceGeneration);
		expect(correlation.observedSha256).toBe(oracleEntry.sha256);
		expect(correlation.descriptorId).not.toBe(correlation.requestId);
		expect(correlation.disposition).toBe('painted');

		const readableElement = document.querySelector(correlation.readableDomSelector);
		expect(
			readableElement,
			`missing readable DOM for ${correlation.surface}:${correlation.itemId}:${correlation.role}`,
		).not.toBeNull();
		expect(readableElement?.textContent ?? '').toContain(oracleEntry.canaryText);
	}
}
