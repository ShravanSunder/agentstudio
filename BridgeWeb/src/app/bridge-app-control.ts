import { z } from 'zod';

import {
	bridgeFileChangeKindSchema,
	bridgeFileClassSchema,
	bridgeReviewRenderModeSchema,
} from '../review-viewer/models/review-projection-models.js';

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
	z.object({
		method: z.literal('bridge.fileTree.search'),
		searchText: z.string(),
	}),
	z.object({
		method: z.literal('bridge.fileTree.setFilter'),
		gitStatusFilter: z.union([z.literal('all'), bridgeFileChangeKindSchema]),
		fileClassFilter: z.union([z.literal('all'), bridgeFileClassSchema]),
	}),
	z.object({
		method: z.literal('bridge.fileTree.revealPath'),
		path: z.string().min(1),
	}),
	z.object({
		method: z.literal('bridge.fileView.showMarkdownPreview'),
		itemId: z.string().min(1).optional(),
	}),
]);

export type BridgeAppControlCommand = z.infer<typeof bridgeAppControlCommandSchema>;

export const bridgeAppControlProbeSchema = z.object({
	sequence: z.number().int().nonnegative(),
	method: bridgeAppControlMethodSchema,
	status: z.enum(['accepted', 'pending', 'rejected']),
	itemId: z.string().min(1).nullable(),
	path: z.string().min(1).nullable(),
	treeSearchText: z.string(),
	gitStatusFilter: z.union([z.literal('all'), bridgeFileChangeKindSchema]),
	fileClassFilter: z.union([z.literal('all'), bridgeFileClassSchema]),
	renderMode: bridgeReviewRenderModeSchema,
	reason: z.string().min(1).nullable(),
});

export type BridgeAppControlProbe = z.infer<typeof bridgeAppControlProbeSchema>;
