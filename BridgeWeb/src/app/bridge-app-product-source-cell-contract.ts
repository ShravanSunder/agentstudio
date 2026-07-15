import { z } from 'zod';

export const bridgeProductSourceCellProjectNameSchema = z.enum([
	'VB-deterministic-fixture',
	'VB-real-worktree',
]);

export const bridgeProductSourceCellSourceKindSchema = z.enum([
	'deterministicFixture',
	'liveGitWorktree',
]);

export const bridgeProductSourceCellSurfaceSchema = z.enum(['file', 'review']);

export const bridgeProductSourceCellTraversalPositionSchema = z.enum(['early', 'middle', 'final']);

export const bridgeProductSourceCellPaintCorrelationSchema = z
	.object({
		contentCacheKey: z.string().min(1),
		contentRequestId: z.string().min(1),
		descriptorId: z.string().min(1),
		disposition: z.literal('painted'),
		itemId: z.string().min(1),
		observedSha256: z.string().regex(/^[a-f0-9]{64}$/u),
		paintedPublicationSequence: z.number().int().nonnegative(),
		position: bridgeProductSourceCellTraversalPositionSchema,
		readableDomItemId: z.string().min(1),
		readableDomSelector: z.string().min(1),
		readableText: z.string().min(1),
		requestId: z.string().min(1),
		role: z.string().min(1),
		selectedItemId: z.string().min(1),
		selectionState: z.enum(['selected', 'visible']),
		semanticItemId: z.string().min(1),
		sourceGeneration: z.number().int().nonnegative(),
		sourceIdentity: z.string().min(1),
		surface: bridgeProductSourceCellSurfaceSchema,
		workerDerivationEpoch: z.number().int().nonnegative(),
	})
	.strict();

export const bridgeProductSourceCellPaintReportSchema = z
	.object({
		bundledPierreVersion: z.string().min(1),
		correlations: z.array(bridgeProductSourceCellPaintCorrelationSchema).min(4),
		oracleUrl: z.string().min(1),
		paneSessionId: z.string().min(1),
		projectName: bridgeProductSourceCellProjectNameSchema,
		providerIdentity: z.string().min(1),
		providerProcessId: z.number().int().positive(),
		runMarker: z.string().min(1),
		sourceChecksum: z.string().regex(/^[a-f0-9]{64}$/u),
		sourceKind: bridgeProductSourceCellSourceKindSchema,
		testEntry: z.string().min(1),
		workerInstanceId: z.string().min(1),
	})
	.strict();

export const bridgeProductSourceCellOracleEntrySchema = z
	.object({
		canaryText: z.string().min(1),
		itemId: z.string().min(1),
		role: z.string().min(1),
		sha256: z.string().regex(/^[a-f0-9]{64}$/u),
		sourceGeneration: z.number().int().nonnegative(),
		sourceIdentity: z.string().min(1),
		surface: bridgeProductSourceCellSurfaceSchema,
	})
	.strict();

export const bridgeProductSourceCellOracleSchema = z
	.object({
		entries: z.array(bridgeProductSourceCellOracleEntrySchema).min(4),
		oracleKind: z.enum(['fixtureManifest', 'gitObjectDatabase']),
		runMarker: z.string().min(1),
		sourceChecksum: z.string().regex(/^[a-f0-9]{64}$/u),
		sourceKind: bridgeProductSourceCellSourceKindSchema,
	})
	.strict();

export const bridgeProductSourceCellMetadataSchema = z
	.object({
		bundledPierreVersion: z.string().min(1),
		oracleUrl: z.string().min(1),
		projectName: bridgeProductSourceCellProjectNameSchema,
		providerIdentity: z.string().min(1),
		providerProcessId: z.number().int().positive(),
		runMarker: z.string().min(1),
		sourceChecksum: z.string().regex(/^[a-f0-9]{64}$/u),
		sourceKind: bridgeProductSourceCellSourceKindSchema,
		testEntry: z.string().min(1),
	})
	.strict();

export const bridgeProductSourceCellContentTraceEntrySchema = z
	.object({
		contentRequestId: z.string().min(1),
		descriptorId: z.string().min(1),
		itemId: z.string().min(1),
		observedSha256: z.string().regex(/^[a-f0-9]{64}$/u),
		paneSessionId: z.string().min(1),
		role: z.string().min(1),
		sourceGeneration: z.number().int().nonnegative(),
		sourceIdentity: z.string().min(1),
		surface: bridgeProductSourceCellSurfaceSchema,
		workerInstanceId: z.string().min(1),
	})
	.strict();

export const bridgeProductSourceCellContentTraceSchema = z
	.object({
		entries: z.array(bridgeProductSourceCellContentTraceEntrySchema).readonly(),
		requests: z.array(z.string().min(1)).readonly(),
	})
	.strict();

export type BridgeProductSourceCellPaintCorrelation = z.infer<
	typeof bridgeProductSourceCellPaintCorrelationSchema
>;
export type BridgeProductSourceCellPaintReport = z.infer<
	typeof bridgeProductSourceCellPaintReportSchema
>;
export type BridgeProductSourceCellOracle = z.infer<typeof bridgeProductSourceCellOracleSchema>;
export type BridgeProductSourceCellMetadata = z.infer<typeof bridgeProductSourceCellMetadataSchema>;
export type BridgeProductSourceCellContentTraceEntry = z.infer<
	typeof bridgeProductSourceCellContentTraceEntrySchema
>;
export type BridgeProductSourceCellProjectName = z.infer<
	typeof bridgeProductSourceCellProjectNameSchema
>;
export type BridgeProductSourceCellSourceKind = z.infer<
	typeof bridgeProductSourceCellSourceKindSchema
>;
