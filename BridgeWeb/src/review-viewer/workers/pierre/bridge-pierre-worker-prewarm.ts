import type { SupportedLanguages } from '@pierre/diffs';
import { getOrCreateWorkerPoolSingleton, type WorkerPoolManager } from '@pierre/diffs/worker';

import {
	ensureBridgeCodeViewThemeResolved,
	bridgePierreDarkThemeName,
} from '../../code-view/bridge-code-view-theme.js';
import {
	bridgePierreDefaultWorkerScriptUrl,
	createBridgePierreBlobWorkerFactory,
	createBridgePierreWorkerHighlighterOptions,
	createBridgePierreWorkerPoolOptions,
} from './bridge-pierre-worker-pool.js';

export interface BridgePierreWorkerPoolPrewarmRequest {
	readonly languages: readonly SupportedLanguages[];
}

export interface PrewarmBridgePierreWorkerPoolProps extends BridgePierreWorkerPoolPrewarmRequest {
	readonly enabled?: boolean;
	readonly ensureCodeViewThemeResolved?: () => Promise<void>;
	readonly fetchWorkerSource?: (workerScriptUrl: string) => Promise<string>;
	readonly getWorkerPoolManager?: (props: {
		readonly workerFactory: () => Worker;
	}) => WorkerPoolManager;
	readonly workerFactory?: () => Worker;
}

const prewarmPromisesBySignature = new Map<string, Promise<void>>();

export function prewarmBridgePierreWorkerPool(
	props: PrewarmBridgePierreWorkerPoolProps,
): Promise<void> {
	if (props.enabled === false || typeof window === 'undefined') {
		return Promise.resolve();
	}
	const languages = normalizedPrewarmLanguages(props.languages);
	const signature = languages.join('|');
	const existingPrewarmPromise = prewarmPromisesBySignature.get(signature);
	if (existingPrewarmPromise !== undefined) {
		return existingPrewarmPromise;
	}

	const prewarmPromise = runBridgePierreWorkerPoolPrewarm({
		...props,
		languages,
	}).catch((error: unknown): void => {
		prewarmPromisesBySignature.delete(signature);
		if (typeof document !== 'undefined') {
			document.documentElement.dataset['bridgePierreWorkerPoolPrewarmState'] = 'failed';
			document.documentElement.dataset['bridgePierreWorkerPoolPrewarmFailure'] =
				error instanceof Error ? error.name : 'Error';
		}
	});
	prewarmPromisesBySignature.set(signature, prewarmPromise);
	return prewarmPromise;
}

export function resetBridgePierreWorkerPoolPrewarmForTest(): void {
	prewarmPromisesBySignature.clear();
}

async function runBridgePierreWorkerPoolPrewarm(
	props: Required<Pick<PrewarmBridgePierreWorkerPoolProps, 'languages'>> &
		Omit<PrewarmBridgePierreWorkerPoolProps, 'languages'>,
): Promise<void> {
	if (typeof document !== 'undefined') {
		document.documentElement.dataset['bridgePierreWorkerPoolPrewarmState'] = 'warming';
		document.documentElement.dataset['bridgePierreWorkerPoolPrewarmLanguages'] =
			props.languages.join(',');
		document.documentElement.dataset['bridgePierreWorkerPoolPrewarmTheme'] =
			bridgePierreDarkThemeName;
		delete document.documentElement.dataset['bridgePierreWorkerPoolPrewarmFailure'];
	}
	const ensureThemeResolved =
		props.ensureCodeViewThemeResolved ?? ensureBridgeCodeViewThemeResolved;
	await ensureThemeResolved();
	const workerFactory =
		props.workerFactory ??
		(await loadBridgePierreWorkerFactory(
			props.fetchWorkerSource === undefined ? {} : { fetchWorkerSource: props.fetchWorkerSource },
		));
	const getWorkerPoolManager = props.getWorkerPoolManager ?? defaultGetWorkerPoolManager;
	const workerPool = getWorkerPoolManager({ workerFactory });
	subscribeToPrewarmReadinessUntilSettled(workerPool);
	await workerPool.initialize([...props.languages]);
	if (typeof document !== 'undefined') {
		document.documentElement.dataset['bridgePierreWorkerPoolPrewarmState'] = 'ready';
	}
}

async function loadBridgePierreWorkerFactory(props: {
	readonly fetchWorkerSource?: (workerScriptUrl: string) => Promise<string>;
}): Promise<() => Worker> {
	const fetchWorkerSource = props.fetchWorkerSource ?? defaultFetchWorkerSource;
	const workerSource = await fetchWorkerSource(bridgePierreDefaultWorkerScriptUrl);
	return createBridgePierreBlobWorkerFactory({ workerSource }).workerFactory;
}

async function defaultFetchWorkerSource(workerScriptUrl: string): Promise<string> {
	if (typeof fetch === 'undefined') {
		throw new Error('Bridge Pierre prewarm requires fetch');
	}
	const response = await fetch(workerScriptUrl);
	if (!response.ok) {
		throw new Error(`Bridge Pierre prewarm failed to load worker: ${response.status}`);
	}
	return await response.text();
}

function defaultGetWorkerPoolManager(props: {
	readonly workerFactory: () => Worker;
}): WorkerPoolManager {
	return getOrCreateWorkerPoolSingleton({
		highlighterOptions: createBridgePierreWorkerHighlighterOptions(),
		poolOptions: createBridgePierreWorkerPoolOptions({
			workerFactory: props.workerFactory,
		}),
	});
}

function subscribeToPrewarmReadinessUntilSettled(workerPool: WorkerPoolManager): void {
	if (typeof document === 'undefined') {
		return;
	}
	let unsubscribe: (() => void) | null = null;
	unsubscribe = workerPool.subscribeToStatChanges((stats): void => {
		document.documentElement.dataset['bridgePierreWorkerPoolPrewarmManagerState'] =
			stats.managerState;
		if (stats.managerState === 'initialized') {
			document.documentElement.dataset['bridgePierreWorkerPoolPrewarmState'] = 'ready';
			unsubscribe?.();
			return;
		}
		if (stats.workersFailed) {
			document.documentElement.dataset['bridgePierreWorkerPoolPrewarmState'] = 'failed';
			unsubscribe?.();
		}
	});
}

function normalizedPrewarmLanguages(
	languages: readonly SupportedLanguages[],
): readonly SupportedLanguages[] {
	const normalizedLanguages: SupportedLanguages[] = [];
	const seenLanguages = new Set<string>();
	for (const language of languages) {
		if (seenLanguages.has(language)) {
			continue;
		}
		seenLanguages.add(language);
		normalizedLanguages.push(language);
	}
	return normalizedLanguages;
}
