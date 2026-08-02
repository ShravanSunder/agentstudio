import { z } from 'zod';

import { bridgeFileTreeSearchTextMaximumLength } from '../core/models/bridge-file-tree-search.js';
import {
	bridgeFileChangeKindSchema,
	bridgeReviewFilterCategorySchema,
	bridgeReviewRenderModeSchema,
	bridgeReviewSearchModeSchema,
} from '../review-viewer/models/review-projection-models.js';

export const bridgeViewerCategoryFilterSchema = z.union([
	z.literal('all'),
	bridgeReviewFilterCategorySchema,
]);

export const bridgeFileTreeFilterCandidateSchema = z.discriminatedUnion('surface', [
	z
		.object({
			surface: z.literal('files'),
			categoryFilter: bridgeViewerCategoryFilterSchema,
		})
		.strict(),
	z
		.object({
			surface: z.literal('review'),
			gitStatusFilter: z.union([z.literal('all'), bridgeFileChangeKindSchema]),
			categoryFilter: bridgeViewerCategoryFilterSchema,
			showBinary: z.boolean(),
			showLarge: z.boolean(),
		})
		.strict(),
]);

export type BridgeFileTreeFilterCandidate = z.infer<typeof bridgeFileTreeFilterCandidateSchema>;
export type BridgeViewerCategoryFilter = z.infer<typeof bridgeViewerCategoryFilterSchema>;

const bridgeFileTreeSearchModeCandidateSchema = z.discriminatedUnion('kind', [
	z.object({ kind: z.literal('text') }).strict(),
	z.object({ kind: z.literal('regex') }).strict(),
]);

const bridgeFileTreeSearchCandidateSchema = z
	.object({
		method: z.literal('bridge.fileTree.search'),
		searchText: z.string(),
		searchMode: bridgeFileTreeSearchModeCandidateSchema,
	})
	.strict();

const bridgeFileTreeSearchCommandSchema = bridgeFileTreeSearchCandidateSchema.extend({
	searchText: z.string().max(bridgeFileTreeSearchTextMaximumLength),
});

export const bridgeAppControlMethodSchema = z.enum([
	'bridge.diff.scrollToFile',
	'bridge.diff.expandFile',
	'bridge.diff.collapseFile',
	'bridge.fileTree.search',
	'bridge.fileTree.setFilter',
	'bridge.fileTree.revealPath',
	'bridge.fileView.showMarkdownPreview',
]);

export const bridgeAppControlCommandSchema = z.discriminatedUnion('method', [
	z.object({
		method: z.literal('bridge.diff.scrollToFile'),
		itemId: z.string().min(1),
	}),
	z.object({
		method: z.literal('bridge.diff.expandFile'),
		itemId: z.string().min(1),
	}),
	z.object({
		method: z.literal('bridge.diff.collapseFile'),
		itemId: z.string().min(1),
	}),
	bridgeFileTreeSearchCommandSchema,
	z
		.object({
			method: z.literal('bridge.fileTree.setFilter'),
			filter: bridgeFileTreeFilterCandidateSchema,
		})
		.strict(),
	z.object({
		method: z.literal('bridge.fileTree.revealPath'),
		path: z.string().min(1),
	}),
	z.object({
		method: z.literal('bridge.fileView.showMarkdownPreview'),
		itemId: z.string().min(1).optional(),
	}),
]);

export type BridgeAppControlCommandRejectionReason =
	| 'invalid_control_command'
	| 'search_query_too_long';

export function bridgeAppControlCommandRejectionReason(
	detail: unknown,
): BridgeAppControlCommandRejectionReason {
	const candidate = bridgeFileTreeSearchCandidateSchema.safeParse(detail);
	return candidate.success &&
		candidate.data.searchText.length > bridgeFileTreeSearchTextMaximumLength
		? 'search_query_too_long'
		: 'invalid_control_command';
}

export type BridgeAppControlCommand = z.infer<typeof bridgeAppControlCommandSchema>;

export const bridgeAppControlProbeSchema = z.object({
	sequence: z.number().int().nonnegative(),
	method: bridgeAppControlMethodSchema,
	status: z.enum(['accepted', 'pending', 'rejected']),
	itemId: z.string().min(1).nullable(),
	path: z.string().min(1).nullable(),
	treeSearchText: z.string(),
	treeSearchMode: bridgeReviewSearchModeSchema,
	filterSurface: z.enum(['files', 'review']),
	gitStatusFilter: z.union([z.literal('all'), bridgeFileChangeKindSchema]),
	categoryFilter: bridgeViewerCategoryFilterSchema,
	showBinary: z.boolean(),
	showLarge: z.boolean(),
	renderMode: bridgeReviewRenderModeSchema,
	reason: z.string().min(1).nullable(),
});

export type BridgeAppControlProbe = z.infer<typeof bridgeAppControlProbeSchema>;
