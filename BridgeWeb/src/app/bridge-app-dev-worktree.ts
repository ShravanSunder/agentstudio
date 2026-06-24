import { z } from 'zod';

import {
	parseBridgeCoreResourceUrl,
	type BridgeCoreResourceUrl,
} from '../core/resources/bridge-resource-url.js';
import {
	worktreeFileProtocolFrameSchema,
	worktreeFileSurfaceSourceIdentitySchema,
	worktreeTreeVirtualizedSizeFactsSchema,
	type WorktreeFileProtocolFrame,
} from '../features/worktree-file/models/worktree-file-protocol-models.js';
import type { WorktreeFileSurfaceRuntimeFetchResourceProps } from '../worktree-file-surface/worktree-file-surface-runtime.js';

export interface BridgeAppDevWorktreeBackend {
	readonly fetchWorktreeFileResource: (
		props: WorktreeFileSurfaceRuntimeFetchResourceProps,
	) => Promise<string>;
	readonly loadWorktreeFileFrames: () => Promise<readonly WorktreeFileProtocolFrame[]>;
}

const worktreeFileContentEndpointPrefix = '/__bridge-worktree/file-content/';
const worktreeSurfaceEndpoint = '/__bridge-worktree/surface';
const worktreeForwardedSearchParamNames: readonly string[] = ['scenario'];
const bridgeWorktreeAllowedResourceKindsByProtocol = {
	'worktree-file': new Set(['worktree.fileContent', 'worktree.treeWindow']),
};

const bridgeWorktreeSurfaceResponseSchema = z
	.object({
		frames: z.array(worktreeFileProtocolFrameSchema),
		source: worktreeFileSurfaceSourceIdentitySchema,
		treeSizeFacts: worktreeTreeVirtualizedSizeFactsSchema,
	})
	.strict();

export function installBridgeAppDevWorktreeBackend(): BridgeAppDevWorktreeBackend {
	const forwardedSearchParams = bridgeWorktreeForwardedSearchParams(window.location.search);
	document.documentElement.setAttribute('data-bridge-app-protocol', 'worktree-file');
	window.addEventListener(
		'beforeunload',
		(): void => {
			document.documentElement.removeAttribute('data-bridge-app-protocol');
		},
		{ once: true },
	);
	return {
		fetchWorktreeFileResource: async (
			resourceProps: WorktreeFileSurfaceRuntimeFetchResourceProps,
		): Promise<string> => {
			const parsedResourceUrl = parseBridgeCoreResourceUrl(resourceProps.resourceUrl, {
				allowedResourceKindsByProtocol: bridgeWorktreeAllowedResourceKindsByProtocol,
			});
			if (parsedResourceUrl === null || parsedResourceUrl.resourceKind !== 'worktree.fileContent') {
				throw new Error('Invalid Bridge worktree file resource URL');
			}
			const response = await fetch(
				bridgeWorktreeEndpoint(
					`${worktreeFileContentEndpointPrefix}${encodeURIComponent(parsedResourceUrl.opaqueId)}`,
					bridgeWorktreeFileContentSearchParams({
						forwardedSearchParams,
						parsedResourceUrl,
					}),
				),
				{ signal: resourceProps.signal },
			);
			if (!response.ok) {
				throw new Error(`Bridge worktree file content request failed: ${response.status}`);
			}
			return await response.text();
		},
		loadWorktreeFileFrames: async (): Promise<readonly WorktreeFileProtocolFrame[]> => {
			const response = await fetch(
				bridgeWorktreeEndpoint(worktreeSurfaceEndpoint, forwardedSearchParams),
			);
			if (!response.ok) {
				throw new Error(`Bridge worktree surface request failed: ${response.status}`);
			}
			const surfaceResponse = bridgeWorktreeSurfaceResponseSchema.parse(await response.json());
			return surfaceResponse.frames;
		},
	};
}

export function bridgeWorktreeForwardedSearchParams(search: string): URLSearchParams {
	const sourceSearchParams = new URLSearchParams(search);
	const forwardedSearchParams = new URLSearchParams();
	for (const searchParamName of worktreeForwardedSearchParamNames) {
		const value = sourceSearchParams.get(searchParamName);
		if (value !== null && value.length > 0) {
			forwardedSearchParams.set(searchParamName, value);
		}
	}
	return forwardedSearchParams;
}

function bridgeWorktreeFileContentSearchParams(props: {
	readonly forwardedSearchParams: URLSearchParams;
	readonly parsedResourceUrl: BridgeCoreResourceUrl;
}): URLSearchParams {
	const contentSearchParams = new URLSearchParams(props.forwardedSearchParams);
	if (props.parsedResourceUrl.generation !== undefined) {
		contentSearchParams.set('generation', String(props.parsedResourceUrl.generation));
	}
	if (props.parsedResourceUrl.cursor !== undefined) {
		contentSearchParams.set('cursor', props.parsedResourceUrl.cursor);
	}
	return contentSearchParams;
}

function bridgeWorktreeEndpoint(path: string, searchParams: URLSearchParams): string {
	const query = searchParams.toString();
	return query.length === 0 ? path : `${path}?${query}`;
}
