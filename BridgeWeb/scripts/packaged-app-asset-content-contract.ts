import { readFile } from 'node:fs/promises';
import { join } from 'node:path';

const bridgeCommWorkerAssetKind = 'bridge-comm-worker';
const bridgeProductRoutes = new Set([
	'agentstudio://rpc/command',
	'agentstudio://rpc/stream',
	'agentstudio://rpc/content',
]);
const devOnlyBridgeWebReferenceFragments: readonly string[] = [
	'/src/app/bridge-app-bootstrap.tsx',
	'/src/app/bridge-app-dev-bootstrap.tsx',
	'bridge-app-dev-bootstrap',
	'bridge-app-dev-fixture',
	'bridge-viewer-mocked-backend',
	'bridge-viewer/test-support',
	'review-viewer/test-support',
	'bridge-product-dev-routes',
	'/__bridge-product/',
];

interface PackagedAssetPath {
	readonly bytes: number;
	readonly path: string;
	readonly sha256: string;
}

interface PackagedWorkerAssetPath extends PackagedAssetPath {
	readonly agentStudioAppUrl: string;
	readonly kind: string;
	readonly source: 'packagedAppAsset';
	readonly workerKind: string;
}

export interface ValidatePackagedAppAssetContentsProps {
	readonly appDirectoryPath: string;
	readonly manifest: {
		readonly schemaVersion: number;
		readonly entrypoints: {
			readonly mainScript: PackagedAssetPath;
			readonly auxiliaryScripts: readonly PackagedAssetPath[];
			readonly styles: readonly PackagedAssetPath[];
		};
		readonly workers: readonly PackagedWorkerAssetPath[];
	};
}

export async function validatePackagedAppAssetContents(
	props: ValidatePackagedAppAssetContentsProps,
): Promise<void> {
	await Promise.all(
		[
			props.manifest.entrypoints.mainScript,
			...props.manifest.entrypoints.auxiliaryScripts,
			...props.manifest.entrypoints.styles,
			...props.manifest.workers,
		].map(async (asset: PackagedAssetPath): Promise<void> => {
			const assetContent = await readFile(join(props.appDirectoryPath, asset.path), 'utf8');
			validateNoDevOnlyBridgeWebReferences(assetContent);
			validateNoExternalCssResourceLoads({ assetPath: asset.path, assetContent });
		}),
	);
	const commWorkerAsset = props.manifest.workers.find(
		(worker): boolean => worker.kind === bridgeCommWorkerAssetKind,
	);
	if (commWorkerAsset === undefined) return;
	const commWorkerSource = await readFile(
		join(props.appDirectoryPath, commWorkerAsset.path),
		'utf8',
	);
	for (const route of bridgeProductRoutes) {
		if (!commWorkerSource.includes(route)) {
			throw new Error(`Packaged Bridge comm worker is missing product route: ${route}`);
		}
	}
}

export function validateNoDevOnlyBridgeWebReferences(value: string): void {
	for (const devOnlyReference of devOnlyBridgeWebReferenceFragments) {
		if (value.includes(devOnlyReference)) {
			throw new Error(
				`Packaged app output contains dev-only BridgeWeb reference: ${devOnlyReference}`,
			);
		}
	}
}

function validateNoExternalCssResourceLoads(props: {
	readonly assetPath: string;
	readonly assetContent: string;
}): void {
	if (!props.assetPath.endsWith('.css')) return;
	const externalCssResourcePattern =
		/(?:@import\s+(?:url\()?["']?(?:https?:|\/\/|data:|blob:|file:)|url\(\s*["']?(?:https?:|\/\/|data:|blob:|file:))/iu;
	if (externalCssResourcePattern.test(props.assetContent)) {
		throw new Error(`Packaged CSS asset contains external resource load: ${props.assetPath}`);
	}
}
