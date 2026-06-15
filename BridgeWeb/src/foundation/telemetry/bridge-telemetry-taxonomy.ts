import { z } from 'zod';

export const bridgeTelemetryPlaneSchema = z.enum(['data', 'control', 'observability']);
export const bridgeTelemetryPrioritySchema = z.enum(['hot', 'warm', 'cold', 'best_effort']);
export const bridgeTelemetrySliceSchema = z.enum([
	'diff_status',
	'diff_package_metadata',
	'diff_package_delta',
	'diff_files',
	'review_threads',
	'review_viewed_files',
	'connection_health',
	'command_acks',
	'review_rpc',
	'content_fetch',
	'telemetry_batch',
	'telemetry_ingest',
	'telemetry_drop',
	'unknown',
]);

export type BridgeTelemetryPlane = z.infer<typeof bridgeTelemetryPlaneSchema>;
export type BridgeTelemetryPriority = z.infer<typeof bridgeTelemetryPrioritySchema>;
export type BridgeTelemetrySlice = z.infer<typeof bridgeTelemetrySliceSchema>;

export function planeForBridgeTelemetrySlice(slice: BridgeTelemetrySlice): BridgeTelemetryPlane {
	switch (slice) {
		case 'connection_health':
		case 'command_acks':
		case 'review_rpc':
			return 'control';
		case 'telemetry_batch':
		case 'telemetry_ingest':
		case 'telemetry_drop':
			return 'observability';
		case 'diff_status':
		case 'diff_package_metadata':
		case 'diff_package_delta':
		case 'diff_files':
		case 'review_threads':
		case 'review_viewed_files':
		case 'content_fetch':
		case 'unknown':
			return 'data';
	}
	return 'data';
}

export function priorityForBridgeTelemetrySlice(
	slice: BridgeTelemetrySlice,
): BridgeTelemetryPriority {
	switch (slice) {
		case 'diff_status':
		case 'connection_health':
		case 'content_fetch':
			return 'hot';
		case 'diff_package_delta':
		case 'review_threads':
		case 'review_viewed_files':
		case 'command_acks':
		case 'review_rpc':
			return 'warm';
		case 'telemetry_batch':
		case 'telemetry_ingest':
		case 'telemetry_drop':
			return 'best_effort';
		case 'diff_package_metadata':
		case 'diff_files':
		case 'unknown':
			return 'cold';
	}
	return 'cold';
}
