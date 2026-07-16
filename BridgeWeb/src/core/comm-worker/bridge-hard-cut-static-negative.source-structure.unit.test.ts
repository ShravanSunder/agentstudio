import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

import { describe, expect, test } from 'vitest';

type BridgeHardCutOwnerGroup =
	| 'feature-resource-get'
	| 'legacy-file-fe-authority'
	| 'legacy-main-review-authority'
	| 'legacy-telemetry-transport'
	| 'page-transport-compatibility'
	| 'page-review-intake-materialization'
	| 'whole-item-private-pierre';

interface BridgeHardCutOwnerRuleBase {
	readonly description: string;
	readonly group: BridgeHardCutOwnerGroup;
	readonly relativePath: string;
}

interface BridgeHardCutOwnerFileRule extends BridgeHardCutOwnerRuleBase {
	readonly kind: 'ownerFile';
}

interface BridgeHardCutSourceSignatureRule extends BridgeHardCutOwnerRuleBase {
	readonly kind: 'sourceSignature';
	readonly signatures: readonly string[];
}

type BridgeHardCutOwnerRule = BridgeHardCutOwnerFileRule | BridgeHardCutSourceSignatureRule;

interface BridgeHardCutViolation {
	readonly description: string;
	readonly group: BridgeHardCutOwnerGroup;
	readonly relativePath: string;
}

const bridgeWebRoot = fileURLToPath(new URL('../../../', import.meta.url));

const reviewIntakeEvent = joinFragments('__bridge_', 'intake_', 'json');
const reviewContentRouteHandler = joinFragments('handleBridgeWorktree', 'ReviewContentRequest');
const reviewMetadataRouteHandler = joinFragments('handleBridgeWorktree', 'ReviewMetadataRequest');
const legacyFileRuntimeFactory = joinFragments('createWorktreeFile', 'SurfaceRuntime');
const legacyContentLoader = joinFragments('loadBridge', 'ContentResource');
const legacyDiagnosticResourceFetch = joinFragments('request.', 'resourceUrl');
const privatePierreFetch = joinFragments('fetch', '(descriptor.resourceUrl)');
const receiptOnlyPierreStatus = joinFragments('status:', "'", 'enqueued', "'");
const wholeItemPierrePayload = joinFragments('kind:', "'", 'codeViewFileItem', "'");
const wholeDiffPierrePayload = joinFragments('kind:', "'", 'codeViewDiffItem', "'");
const wholeItemPierreParser = joinFragments('parseDiff', 'FromFile');
const legacyReviewIntakeHook = joinFragments('useBridgeReview', 'IntakeController');
const legacyReviewProjectionHook = joinFragments('useBridgeReview', 'ProjectionCoordinator');
const legacyReviewProjectionWorkerFactory = joinFragments(
	'createBridgeReviewProjection',
	'WebWorkerClient',
);
const legacyReviewPackageState = joinFragments('useState<BridgeReview', 'Package');
const legacyReviewShellPackageProp = joinFragments(
	'readonly review',
	'Package: BridgeReviewPackage',
);
const legacyReviewShellProjectionProp = joinFragments(
	'readonly projection:',
	' BridgeReviewProjectionResult',
);
const legacyReviewProductDisplayPath = sourcePath(
	'src',
	'app',
	joinFragments('bridge-app-review-', 'product-display.ts'),
);
const legacyReviewModePath = sourcePath(
	'src',
	'app',
	joinFragments('bridge-app-review-', 'viewer-mode.tsx'),
);
const legacyReviewShellBoundaryPath = sourcePath(
	'src',
	'app',
	joinFragments('bridge-app-review-viewer-', 'shell-boundary.tsx'),
);
const legacyReviewSourceStructureTestPath = sourcePath(
	'src',
	'review-viewer',
	joinFragments('review-viewer-source-', 'structure.unit.test.ts'),
);

const bridgeHardCutOwnerRules = [
	ownerFileRule(
		'page-transport-compatibility',
		sourcePath('src', 'bridge', joinFragments('bridge-rpc-', 'client.ts')),
		'generic page JSON-RPC compatibility client',
	),
	ownerFileRule(
		'page-transport-compatibility',
		sourcePath('src', 'bridge', joinFragments('bridge-push-', 'envelope.ts')),
		'legacy page push envelope contract',
	),
	ownerFileRule(
		'page-transport-compatibility',
		sourcePath('src', 'bridge', joinFragments('bridge-push-', 'receiver.ts')),
		'legacy page push receiver',
	),
	ownerFileRule(
		'feature-resource-get',
		sourcePath(
			'src',
			'app',
			'diagnostics',
			joinFragments('bridge-worker-fetch-probe-worker-', 'entry.ts'),
		),
		'legacy feature-resource worker diagnostic entry',
	),
	ownerFileRule(
		'page-review-intake-materialization',
		sourcePath('src', 'app', joinFragments('bridge-app-review-', 'intake-receiver.ts')),
		'page-owned Review intake sequencing receiver',
	),
	ownerFileRule(
		'feature-resource-get',
		sourcePath(
			'src',
			'features',
			'review',
			'protocol',
			joinFragments('review-metadata-frame-', 'builder.ts'),
		),
		'legacy Review metadata frame and feature resource descriptor builder',
	),
	ownerFileRule(
		'feature-resource-get',
		sourcePath(
			'scripts',
			'dev-server',
			joinFragments('bridge-worktree-review-dev-', 'provider.ts'),
		),
		'dormant Review metadata/resource development provider',
	),
	ownerFileRule(
		'feature-resource-get',
		sourcePath('src', 'core', 'resources', joinFragments('bridge-resource-', 'registry.ts')),
		'legacy feature resource descriptor registry',
	),
	ownerFileRule(
		'feature-resource-get',
		sourcePath('src', 'core', 'resources', joinFragments('bridge-resource-', 'url.ts')),
		'legacy feature resource URL parser',
	),
	ownerFileRule(
		'feature-resource-get',
		sourcePath('src', 'core', 'models', joinFragments('bridge-resource-', 'descriptor.ts')),
		'legacy feature resource descriptor schema',
	),
	sourceSignatureRule(
		'feature-resource-get',
		sourcePath(
			'src',
			'app',
			'diagnostics',
			joinFragments('bridge-product-stream-webkit-feasibility-worker-', 'entry.ts'),
		),
		'legacy feature resource fetch branch in the retained product-stream diagnostic worker',
		[legacyDiagnosticResourceFetch],
	),
	sourceSignatureRule(
		'page-review-intake-materialization',
		sourcePath('src', 'app', joinFragments('bridge-app-review-', 'intake-controller.ts')),
		'page-owned Review intake replay and event carrier',
		[quotedSourceToken(reviewIntakeEvent)],
	),
	ownerFileRule(
		'page-review-intake-materialization',
		sourcePath('src', 'app', joinFragments('bridge-app-review-', 'controller.ts')),
		'page-owned Review protocol application and package materialization',
	),
	ownerFileRule(
		'page-review-intake-materialization',
		sourcePath('src', 'app', joinFragments('bridge-app-review-', 'metadata-package.ts')),
		'page-owned Review package projection and resource-handle materialization',
	),
	ownerFileRule(
		'page-review-intake-materialization',
		sourcePath('src', 'core', 'intake', joinFragments('bridge-intake-', 'carrier.ts')),
		'legacy page intake event carrier',
	),
	ownerFileRule(
		'page-review-intake-materialization',
		sourcePath('src', 'core', 'intake', joinFragments('bridge-intake-', 'receiver.ts')),
		'legacy page intake receiver contract',
	),
	ownerFileRule(
		'page-review-intake-materialization',
		sourcePath(
			'src',
			'features',
			'review',
			'materialization',
			joinFragments('review-', 'materializer.ts'),
		),
		'legacy main-thread Review frame materializer',
	),
	ownerFileRule(
		'legacy-main-review-authority',
		legacyReviewProductDisplayPath,
		'temporary main-thread Review product-to-package reconstruction adapter',
	),
	sourceSignatureRule(
		'legacy-main-review-authority',
		legacyReviewModePath,
		'main Review package, intake, and projection authority',
		[
			callSourceToken(legacyReviewIntakeHook),
			callSourceToken(legacyReviewProjectionHook),
			callSourceToken(legacyReviewProjectionWorkerFactory),
			legacyReviewPackageState,
		],
	),
	sourceSignatureRule(
		'legacy-main-review-authority',
		legacyReviewShellBoundaryPath,
		'main Review shell package and projection readiness gate',
		[legacyReviewShellPackageProp, legacyReviewShellProjectionProp],
	),
	ownerFileRule(
		'legacy-main-review-authority',
		sourcePath('src', 'review-viewer', 'state', joinFragments('review-viewer-', 'store.ts')),
		'legacy main Review projection store authority',
	),
	ownerFileRule(
		'legacy-main-review-authority',
		sourcePath(
			'src',
			'review-viewer',
			'projections',
			joinFragments('use-review-projection-', 'coordinator.ts'),
		),
		'legacy main Review projection coordinator',
	),
	ownerFileRule(
		'legacy-main-review-authority',
		sourcePath(
			'src',
			'review-viewer',
			'workers',
			'projection',
			joinFragments('review-projection-worker-', 'entry.ts'),
		),
		'feature-owned Review projection worker entry',
	),
	ownerFileRule(
		'legacy-main-review-authority',
		sourcePath(
			'src',
			'review-viewer',
			'workers',
			'projection',
			joinFragments('review-projection-worker-', 'client.ts'),
		),
		'feature-owned Review projection worker client',
	),
	ownerFileRule(
		'legacy-main-review-authority',
		sourcePath(
			'src',
			'review-viewer',
			'workers',
			'projection',
			joinFragments('review-projection-worker-', 'transport.ts'),
		),
		'feature-owned Review projection worker transport',
	),
	ownerFileRule(
		'legacy-main-review-authority',
		sourcePath(
			'src',
			'review-viewer',
			'workers',
			'projection',
			joinFragments('review-projection-', 'sync-client.ts'),
		),
		'legacy synchronous Review projection client',
	),
	ownerFileRule(
		'legacy-main-review-authority',
		sourcePath(
			'src',
			'review-viewer',
			'workers',
			'projection',
			joinFragments('review-projection-worker-', 'planner.ts'),
		),
		'feature-owned Review projection worker planner',
	),
	ownerFileRule(
		'legacy-main-review-authority',
		sourcePath(
			'src',
			'review-viewer',
			'workers',
			'projection',
			joinFragments('review-projection-worker-', 'rpc.ts'),
		),
		'feature-owned Review projection worker RPC',
	),
	sourceSignatureRule(
		'legacy-main-review-authority',
		legacyReviewSourceStructureTestPath,
		'legacy source-structure proof requiring main Review intake or projection hooks',
		[
			positiveContainmentSourceToken(legacyReviewIntakeHook),
			positiveContainmentSourceToken(legacyReviewProjectionHook),
		],
	),
	sourceSignatureRule(
		'legacy-file-fe-authority',
		sourcePath(
			'src',
			'worktree-file-surface',
			joinFragments('worktree-file-surface-', 'runtime.ts'),
		),
		'legacy File runtime, body cache, retry, and demand authority',
		[callSourceToken(legacyFileRuntimeFactory)],
	),
	ownerFileRule(
		'legacy-file-fe-authority',
		sourcePath(
			'src',
			'worktree-file-surface',
			joinFragments('worktree-file-surface-', 'runtime-support.ts'),
		),
		'legacy File runtime cache and executor support',
	),
	ownerFileRule(
		'legacy-file-fe-authority',
		sourcePath('src', 'worktree-file-surface', joinFragments('worktree-file-', 'app.tsx')),
		'legacy standalone File React surface and body owner',
	),
	ownerFileRule(
		'legacy-file-fe-authority',
		sourcePath(
			'src',
			'features',
			'worktree-file',
			'demand',
			joinFragments('worktree-file-', 'demand-policy.ts'),
		),
		'legacy File FE demand membership authority',
	),
	ownerFileRule(
		'legacy-file-fe-authority',
		sourcePath(
			'src',
			'features',
			'worktree-file',
			'materialization',
			joinFragments('worktree-file-', 'materializer.ts'),
		),
		'legacy File FE frame materializer',
	),
	ownerFileRule(
		'legacy-file-fe-authority',
		sourcePath(
			'src',
			'features',
			'worktree-file',
			'state',
			joinFragments('worktree-file-', 'state.ts'),
		),
		'legacy File FE cache and retry state authority',
	),
	ownerFileRule(
		'legacy-file-fe-authority',
		sourcePath(
			'src',
			'features',
			'worktree-file',
			'models',
			joinFragments('worktree-file-', 'protocol-models.ts'),
		),
		'legacy File FE frame and resource protocol authority',
	),
	sourceSignatureRule(
		'feature-resource-get',
		sourcePath('src', 'foundation', 'content', joinFragments('content-resource-', 'loader.ts')),
		'feature-owned Review resource fetch loader',
		[callSourceToken(legacyContentLoader)],
	),
	ownerFileRule(
		'feature-resource-get',
		sourcePath('src', 'app', joinFragments('bridge-app-dev-', 'worktree-review.ts')),
		'legacy Vite Review feature fetch adapter',
	),
	sourceSignatureRule(
		'feature-resource-get',
		sourcePath('vite.config.ts'),
		'legacy Vite Review metadata GET route',
		[callSourceToken(reviewMetadataRouteHandler)],
	),
	sourceSignatureRule(
		'feature-resource-get',
		sourcePath('vite.config.ts'),
		'legacy Vite Review content GET route',
		[callSourceToken(reviewContentRouteHandler)],
	),
	ownerFileRule(
		'legacy-telemetry-transport',
		sourcePath('src', 'bridge', joinFragments('bridge-telemetry-', 'event-sink.ts')),
		'legacy page telemetry event sink',
	),
	ownerFileRule(
		'legacy-telemetry-transport',
		sourcePath('src', 'foundation', 'telemetry', joinFragments('bridge-telemetry-', 'buffer.ts')),
		'legacy page telemetry buffer',
	),
	ownerFileRule(
		'legacy-telemetry-transport',
		sourcePath('src', 'foundation', 'telemetry', joinFragments('bridge-telemetry-', 'sink.ts')),
		'legacy page telemetry transport sink',
	),
	sourceSignatureRule(
		'whole-item-private-pierre',
		sourcePath('src', 'core', 'comm-worker', joinFragments('bridge-worker-pierre-', 'courier.ts')),
		'receipt-only Pierre courier',
		[receiptOnlyPierreStatus],
	),
	sourceSignatureRule(
		'whole-item-private-pierre',
		sourcePath(
			'src',
			'core',
			'comm-worker',
			joinFragments('bridge-worker-pierre-', 'render-job.ts'),
		),
		'whole-item Pierre render payload',
		[wholeItemPierrePayload, wholeDiffPierrePayload],
	),
	sourceSignatureRule(
		'whole-item-private-pierre',
		sourcePath(
			'src',
			'core',
			'comm-worker',
			joinFragments('bridge-worker-review-pierre-', 'job-planner.ts'),
		),
		'worker-side whole-item Pierre reconstruction',
		[wholeItemPierreParser],
	),
	sourceSignatureRule(
		'whole-item-private-pierre',
		sourcePath(
			'src',
			'review-viewer',
			'workers',
			'pierre',
			joinFragments('bridge-pierre-worker-', 'content-descriptor.ts'),
		),
		'private Pierre worker resource GET capability',
		[privatePierreFetch],
	),
] as const satisfies readonly BridgeHardCutOwnerRule[];

describe('Bridge hard-cut static negatives', () => {
	test('detects canonical and alternate legacy spellings without embedding scanner targets', () => {
		const legacyReviewModeIdentity = `legacy-main-review-authority:${legacyReviewModePath}`;
		const canonicalLegacyReviewModeSources = [
			joinFragments(legacyReviewIntakeHook, '({});'),
			joinFragments(legacyReviewProjectionHook, '({});'),
			joinFragments('const client = ', legacyReviewProjectionWorkerFactory, '();'),
			joinFragments('const state = ', legacyReviewPackageState, ' | null>(null);'),
		];
		const alternateLegacyReviewModeSources = [
			joinFragments(legacyReviewIntakeHook, ' \n ( {} );'),
			joinFragments(legacyReviewProjectionHook, ' \n ( {} );'),
			joinFragments('const client = ', legacyReviewProjectionWorkerFactory, ' \n ( );'),
			joinFragments('const state = useState \n < BridgeReview', 'Package | null > ( null );'),
		];
		const canonicalSources = new Map<string, string>([
			[
				sourcePath('src', 'bridge', joinFragments('bridge-rpc-', 'client.ts')),
				'export const genericRpcCompatibilityClient = true;',
			],
			[
				sourcePath('src', 'bridge', joinFragments('bridge-push-', 'envelope.ts')),
				'export const legacyPushEnvelope = true;',
			],
			[
				sourcePath('src', 'bridge', joinFragments('bridge-push-', 'receiver.ts')),
				'export const legacyPushReceiver = true;',
			],
			[legacyReviewProductDisplayPath, 'export const productDisplayAdapter = true;'],
			[legacyReviewModePath, canonicalLegacyReviewModeSources.join('\n')],
			[
				legacyReviewShellBoundaryPath,
				joinFragments(
					legacyReviewShellPackageProp,
					' | null; ',
					legacyReviewShellProjectionProp,
					' | null;',
				),
			],
			[
				legacyReviewSourceStructureTestPath,
				joinFragments(
					'expect(modeSource)',
					positiveContainmentSourceToken(legacyReviewIntakeHook),
					';',
				),
			],
			[
				sourcePath('src', 'app', joinFragments('bridge-app-review-', 'intake-controller.ts')),
				joinFragments('new CustomEvent(', "'", reviewIntakeEvent, "'", ')'),
			],
			[
				sourcePath(
					'src',
					'worktree-file-surface',
					joinFragments('worktree-file-surface-', 'runtime.ts'),
				),
				joinFragments('export function ', legacyFileRuntimeFactory, '() {}'),
			],
			[
				sourcePath('src', 'foundation', 'content', joinFragments('content-resource-', 'loader.ts')),
				joinFragments('export async function ', legacyContentLoader, '() {}'),
			],
			[
				sourcePath(
					'src',
					'app',
					'diagnostics',
					joinFragments('bridge-product-stream-webkit-feasibility-worker-', 'entry.ts'),
				),
				joinFragments('await fetch(', legacyDiagnosticResourceFetch, ');'),
			],
			[
				sourcePath(
					'src',
					'core',
					'comm-worker',
					joinFragments('bridge-worker-pierre-', 'courier.ts'),
				),
				joinFragments('return { ', receiptOnlyPierreStatus, ' };'),
			],
			[
				sourcePath(
					'src',
					'review-viewer',
					'workers',
					'pierre',
					joinFragments('bridge-pierre-worker-', 'content-descriptor.ts'),
				),
				joinFragments('await ', privatePierreFetch, ';'),
			],
		]);
		const alternateSources = new Map<string, string>([
			[legacyReviewProductDisplayPath, 'export\nconst productDisplayAdapter = true;'],
			[legacyReviewModePath, alternateLegacyReviewModeSources.join('\n')],
			[
				legacyReviewShellBoundaryPath,
				joinFragments(
					'readonly\nreview',
					'Package : BridgeReviewPackage | null; readonly\nprojection : ',
					'BridgeReviewProjectionResult | null;',
				),
			],
			[
				legacyReviewSourceStructureTestPath,
				joinFragments('expect(modeSource) . toContain ( "', legacyReviewProjectionHook, '" );'),
			],
			[
				sourcePath('src', 'app', joinFragments('bridge-app-review-', 'intake-controller.ts')),
				joinFragments('new globalThis.CustomEvent(\n  "', reviewIntakeEvent, '"\n)'),
			],
			[
				sourcePath(
					'src',
					'worktree-file-surface',
					joinFragments('worktree-file-surface-', 'runtime.ts'),
				),
				joinFragments('const runtime = ', legacyFileRuntimeFactory, ' \n ( props );'),
			],
			[
				sourcePath('src', 'foundation', 'content', joinFragments('content-resource-', 'loader.ts')),
				joinFragments('return ', legacyContentLoader, '\n ( props );'),
			],
			[
				sourcePath(
					'src',
					'app',
					'diagnostics',
					joinFragments('bridge-product-stream-webkit-feasibility-worker-', 'entry.ts'),
				),
				joinFragments('await fetch( request . ', 'resourceUrl );'),
			],
			[
				sourcePath(
					'src',
					'core',
					'comm-worker',
					joinFragments('bridge-worker-pierre-', 'courier.ts'),
				),
				joinFragments('return { status : "', 'enqueued', '" };'),
			],
			[
				sourcePath(
					'src',
					'review-viewer',
					'workers',
					'pierre',
					joinFragments('bridge-pierre-worker-', 'content-descriptor.ts'),
				),
				joinFragments('await globalThis.', 'fetch \n ( descriptor.resourceUrl );'),
			],
		]);
		for (const source of canonicalLegacyReviewModeSources) {
			expect(
				scanBridgeHardCutSources(new Map([[legacyReviewModePath, source]])).map(violationIdentity),
			).toContain(legacyReviewModeIdentity);
		}
		for (const source of alternateLegacyReviewModeSources) {
			expect(
				scanBridgeHardCutSources(new Map([[legacyReviewModePath, source]])).map(violationIdentity),
			).toContain(legacyReviewModeIdentity);
		}

		expect(scanBridgeHardCutSources(canonicalSources).map(violationIdentity)).toEqual(
			expect.arrayContaining([
				'page-transport-compatibility:src/bridge/bridge-rpc-client.ts',
				'page-transport-compatibility:src/bridge/bridge-push-envelope.ts',
				'page-transport-compatibility:src/bridge/bridge-push-receiver.ts',
				`legacy-main-review-authority:${legacyReviewProductDisplayPath}`,
				legacyReviewModeIdentity,
				`legacy-main-review-authority:${legacyReviewShellBoundaryPath}`,
				`legacy-main-review-authority:${legacyReviewSourceStructureTestPath}`,
				'page-review-intake-materialization:src/app/bridge-app-review-intake-controller.ts',
				'legacy-file-fe-authority:src/worktree-file-surface/worktree-file-surface-runtime.ts',
				'feature-resource-get:src/foundation/content/content-resource-loader.ts',
				'feature-resource-get:src/app/diagnostics/bridge-product-stream-webkit-feasibility-worker-entry.ts',
				'whole-item-private-pierre:src/core/comm-worker/bridge-worker-pierre-courier.ts',
				'whole-item-private-pierre:src/review-viewer/workers/pierre/bridge-pierre-worker-content-descriptor.ts',
			]),
		);
		expect(scanBridgeHardCutSources(alternateSources).map(violationIdentity)).toEqual(
			expect.arrayContaining([
				`legacy-main-review-authority:${legacyReviewProductDisplayPath}`,
				legacyReviewModeIdentity,
				`legacy-main-review-authority:${legacyReviewShellBoundaryPath}`,
				`legacy-main-review-authority:${legacyReviewSourceStructureTestPath}`,
				'page-review-intake-materialization:src/app/bridge-app-review-intake-controller.ts',
				'legacy-file-fe-authority:src/worktree-file-surface/worktree-file-surface-runtime.ts',
				'feature-resource-get:src/foundation/content/content-resource-loader.ts',
				'feature-resource-get:src/app/diagnostics/bridge-product-stream-webkit-feasibility-worker-entry.ts',
				'whole-item-private-pierre:src/core/comm-worker/bridge-worker-pierre-courier.ts',
				'whole-item-private-pierre:src/review-viewer/workers/pierre/bridge-pierre-worker-content-descriptor.ts',
			]),
		);
	});

	test('permits product POST, telemetry producer, keyed display slices, and typed worker RPC', () => {
		const allowedSource = [
			'await fetch(BRIDGE_PRODUCT_CONTENT_ROUTE, { method: BRIDGE_PRODUCT_REQUEST_METHOD });',
			'telemetryProducer.record(compactSample);',
			'const snapshot = await readProductSessionDiagnostic();',
			'const displayItem: BridgeWorkerReviewDisplayItem = useBridgeReviewItemDisplaySlice(itemId);',
			'const row = useBridgeReviewRowPaintSlice(rowId);',
			'const rpcClient: BridgeWorkerRpcClient = createBridgeWorkerRpcClient(workerPort);',
		].join('\n');

		expect(
			bridgeHardCutOwnerRules
				.filter(isSourceSignatureRule)
				.filter((rule): boolean => sourceMatchesRule(allowedSource, rule)),
		).toEqual([]);
	});

	test('has no named legacy product owners after atomic A0 hard cut', () => {
		const violations = scanBridgeHardCutWorktree();

		expect(violations.map(formatViolation)).toEqual([]);
	});
});

function ownerFileRule(
	group: BridgeHardCutOwnerGroup,
	relativePath: string,
	description: string,
): BridgeHardCutOwnerFileRule {
	return { description, group, kind: 'ownerFile', relativePath };
}

function sourceSignatureRule(
	group: BridgeHardCutOwnerGroup,
	relativePath: string,
	description: string,
	signatures: readonly string[],
): BridgeHardCutSourceSignatureRule {
	return { description, group, kind: 'sourceSignature', relativePath, signatures };
}

function scanBridgeHardCutWorktree(): readonly BridgeHardCutViolation[] {
	return bridgeHardCutOwnerRules.flatMap((rule): readonly BridgeHardCutViolation[] => {
		const absolutePath = join(bridgeWebRoot, rule.relativePath);
		if (!existsSync(absolutePath)) {
			return [];
		}
		if (rule.kind === 'sourceSignature') {
			const source = readFileSync(absolutePath, 'utf8');
			if (!sourceMatchesRule(source, rule)) {
				return [];
			}
		}
		return [violationForRule(rule)];
	});
}

function scanBridgeHardCutSources(
	sourceByRelativePath: ReadonlyMap<string, string>,
): readonly BridgeHardCutViolation[] {
	return bridgeHardCutOwnerRules.flatMap((rule): readonly BridgeHardCutViolation[] => {
		const source = sourceByRelativePath.get(rule.relativePath);
		if (source === undefined) {
			return [];
		}
		if (rule.kind === 'sourceSignature' && !sourceMatchesRule(source, rule)) {
			return [];
		}
		return [violationForRule(rule)];
	});
}

function sourceMatchesRule(source: string, rule: BridgeHardCutSourceSignatureRule): boolean {
	const normalizedSource = normalizeSource(source);
	return rule.signatures.some((signature): boolean =>
		normalizedSource.includes(normalizeSource(signature)),
	);
}

function normalizeSource(source: string): string {
	return source.replaceAll('"', "'").replaceAll(/\s+/gu, '');
}

function violationForRule(rule: BridgeHardCutOwnerRule): BridgeHardCutViolation {
	return {
		description: rule.description,
		group: rule.group,
		relativePath: rule.relativePath,
	};
}

function formatViolation(violation: BridgeHardCutViolation): string {
	return `${violation.group} :: ${violation.relativePath} :: ${violation.description}`;
}

function violationIdentity(violation: BridgeHardCutViolation): string {
	return `${violation.group}:${violation.relativePath}`;
}

function isSourceSignatureRule(
	rule: BridgeHardCutOwnerRule,
): rule is BridgeHardCutSourceSignatureRule {
	return rule.kind === 'sourceSignature';
}

function sourcePath(...components: readonly string[]): string {
	return components.join('/');
}

function joinFragments(...fragments: readonly string[]): string {
	return fragments.join('');
}

function callSourceToken(symbol: string): string {
	return `${symbol}(`;
}

function quotedSourceToken(token: string): string {
	return `'${token}'`;
}

function positiveContainmentSourceToken(token: string): string {
	return `.toContain('${token}')`;
}
