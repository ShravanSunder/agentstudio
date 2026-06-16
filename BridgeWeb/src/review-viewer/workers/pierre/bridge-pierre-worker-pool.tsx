import type { WorkerInitializationRenderOptions, WorkerPoolOptions } from '@pierre/diffs/react';
import { WorkerPoolContextProvider, useWorkerPool } from '@pierre/diffs/react';
import type { ReactElement, ReactNode } from 'react';
import { Fragment, useEffect, useMemo, useState } from 'react';
import { z } from 'zod';

export const bridgePierreWorkerKindSchema = z.enum(['classicWorker', 'moduleWorker']);

export type BridgePierreWorkerKind = z.infer<typeof bridgePierreWorkerKindSchema>;

export const bridgePierreWorkerAssetManifestSchema = z
	.object({
		kind: z.literal('pierre-diffs-shiki'),
		path: z.string().min(1),
		agentStudioAppUrl: z
			.string()
			.regex(/^agentstudio:\/\/app\/.+/u, 'worker asset must resolve through agentstudio://app'),
		workerKind: bridgePierreWorkerKindSchema,
		source: z.literal('packagedAppAsset'),
		bytes: z.number().int().positive(),
		sha256: z.string().regex(/^[a-f0-9]{64}$/u),
	})
	.strict();

export type BridgePierreWorkerAssetManifest = z.infer<typeof bridgePierreWorkerAssetManifestSchema>;

export type BridgePierreWorkerStats = ReturnType<
	NonNullable<ReturnType<typeof useWorkerPool>>['getStats']
>;

export interface CreateBridgePierreWorkerFactoryProps {
	readonly workerScriptUrl?: string | URL;
	readonly workerKind?: BridgePierreWorkerKind;
	readonly createWorker?: (url: string | URL, options?: WorkerOptions) => Worker;
}

export interface CreateBridgePierreWorkerPoolOptionsProps {
	readonly workerFactory: () => Worker;
	readonly poolSize?: number;
	readonly totalASTLRUCacheSize?: number;
}

export interface CreateBridgePierreBlobWorkerFactoryProps {
	readonly workerSource: string;
	readonly workerKind?: BridgePierreWorkerKind;
	readonly createObjectURL?: (blob: Blob) => string;
	readonly revokeObjectURL?: (url: string) => void;
	readonly createWorker?: (url: string | URL, options?: WorkerOptions) => Worker;
}

export interface BridgePierreBlobWorkerFactory {
	readonly workerScriptUrl: string;
	readonly workerFactory: () => Worker;
	readonly revoke: () => void;
}

export interface BridgePierreWorkerPoolProviderProps {
	readonly children: ReactNode;
	readonly enabled?: boolean;
	readonly workerFactory?: () => Worker;
	readonly poolSize?: number;
}

type BridgePierreWorkerPoolLoadState =
	| { readonly kind: 'disabled' }
	| { readonly kind: 'loading' }
	| { readonly kind: 'ready'; readonly workerFactory: () => Worker }
	| { readonly kind: 'failed'; readonly errorMessage: string };

const defaultWorkerScriptUrl = new URL(
	'../workers/pierre-diffs-worker-portable.js',
	import.meta.url,
);
const defaultPoolSize = 2;
const defaultTotalASTLRUCacheSize = 128;

export function createBridgePierreWorkerFactory(
	props: CreateBridgePierreWorkerFactoryProps = {},
): () => Worker {
	const workerScriptUrl = props.workerScriptUrl ?? defaultWorkerScriptUrl;
	const workerKind = props.workerKind ?? 'classicWorker';
	const createWorker = props.createWorker ?? defaultCreateWorker;

	return (): Worker =>
		workerKind === 'moduleWorker'
			? createWorker(workerScriptUrl, { type: 'module' })
			: createWorker(workerScriptUrl);
}

export function createBridgePierreWorkerPoolOptions(
	props: CreateBridgePierreWorkerPoolOptionsProps,
): WorkerPoolOptions {
	return {
		workerFactory: props.workerFactory,
		poolSize: props.poolSize ?? defaultPoolSize,
		totalASTLRUCacheSize: props.totalASTLRUCacheSize ?? defaultTotalASTLRUCacheSize,
	};
}

export function createBridgePierreBlobWorkerFactory(
	props: CreateBridgePierreBlobWorkerFactoryProps,
): BridgePierreBlobWorkerFactory {
	const workerKind = props.workerKind ?? 'classicWorker';
	const createObjectURL = props.createObjectURL ?? URL.createObjectURL.bind(URL);
	const revokeObjectURL = props.revokeObjectURL ?? URL.revokeObjectURL.bind(URL);
	const workerScriptBlob = new Blob([props.workerSource], { type: 'application/javascript' });
	const workerScriptUrl = createObjectURL(workerScriptBlob);
	const workerFactory = createBridgePierreWorkerFactory({
		workerScriptUrl,
		workerKind,
		...(props.createWorker === undefined ? {} : { createWorker: props.createWorker }),
	});

	return {
		workerScriptUrl,
		workerFactory,
		revoke: (): void => {
			revokeObjectURL(workerScriptUrl);
		},
	};
}

export function createBridgePierreWorkerHighlighterOptions(): WorkerInitializationRenderOptions {
	return {
		theme: {
			dark: 'pierre-dark',
			light: 'pierre-dark',
		},
		langs: ['swift', 'typescript', 'javascript', 'markdown', 'json', 'yaml', 'text'],
		preferredHighlighter: 'shiki-js',
		useTokenTransformer: false,
		tokenizeMaxLineLength: 20_000,
	};
}

export function BridgePierreWorkerPoolProvider(
	props: BridgePierreWorkerPoolProviderProps,
): ReactElement {
	const enabled = props.enabled ?? typeof Worker !== 'undefined';
	const workerLoadState = useBridgePierreWorkerPoolLoadState({
		enabled,
		...(props.workerFactory === undefined ? {} : { workerFactory: props.workerFactory }),
	});
	const workerFactory = workerLoadState.kind === 'ready' ? workerLoadState.workerFactory : null;
	const poolOptions = useMemo(() => {
		if (workerFactory === null) {
			return null;
		}

		return createBridgePierreWorkerPoolOptions({
			workerFactory,
			...(props.poolSize === undefined ? {} : { poolSize: props.poolSize }),
		});
	}, [props.poolSize, workerFactory]);
	const highlighterOptions = useMemo(() => createBridgePierreWorkerHighlighterOptions(), []);

	if (!enabled || poolOptions === null) {
		return <Fragment>{props.children}</Fragment>;
	}

	return (
		<WorkerPoolContextProvider highlighterOptions={highlighterOptions} poolOptions={poolOptions}>
			{props.children}
		</WorkerPoolContextProvider>
	);
}

export function useBridgePierreWorkerStats(): BridgePierreWorkerStats | null {
	return useWorkerPool()?.getStats() ?? null;
}

function useBridgePierreWorkerPoolLoadState(props: {
	readonly enabled: boolean;
	readonly workerFactory?: () => Worker;
}): BridgePierreWorkerPoolLoadState {
	const [loadState, setLoadState] = useState<BridgePierreWorkerPoolLoadState>(() =>
		initialWorkerPoolLoadState(props),
	);

	useEffect((): (() => void) | void => {
		if (!props.enabled) {
			setLoadState({ kind: 'disabled' });
			return;
		}
		if (props.workerFactory !== undefined) {
			setLoadState({ kind: 'ready', workerFactory: props.workerFactory });
			return;
		}
		if (
			typeof Worker === 'undefined' ||
			typeof fetch === 'undefined' ||
			typeof URL.createObjectURL !== 'function'
		) {
			setLoadState({
				kind: 'failed',
				errorMessage: 'Worker runtime APIs are unavailable',
			});
			return;
		}

		let didCancel = false;
		let loadedFactory: BridgePierreBlobWorkerFactory | null = null;
		setLoadState({ kind: 'loading' });

		void fetch(defaultWorkerScriptUrl)
			.then(async (response: Response): Promise<string> => {
				if (!response.ok) {
					throw new Error(`Failed to load packaged worker: ${response.status}`);
				}
				return await response.text();
			})
			.then((workerSource: string): void => {
				if (didCancel) {
					return;
				}
				loadedFactory = createBridgePierreBlobWorkerFactory({ workerSource });
				setLoadState({
					kind: 'ready',
					workerFactory: loadedFactory.workerFactory,
				});
			})
			.catch((error: unknown): void => {
				if (didCancel) {
					return;
				}
				setLoadState({
					kind: 'failed',
					errorMessage: error instanceof Error ? error.message : String(error),
				});
			});

		return (): void => {
			didCancel = true;
			loadedFactory?.revoke();
		};
	}, [props.enabled, props.workerFactory]);

	return loadState;
}

function initialWorkerPoolLoadState(props: {
	readonly enabled: boolean;
	readonly workerFactory?: () => Worker;
}): BridgePierreWorkerPoolLoadState {
	if (!props.enabled) {
		return { kind: 'disabled' };
	}
	if (props.workerFactory !== undefined) {
		return { kind: 'ready', workerFactory: props.workerFactory };
	}
	return { kind: 'loading' };
}

function defaultCreateWorker(url: string | URL, options?: WorkerOptions): Worker {
	return new Worker(url, options);
}
