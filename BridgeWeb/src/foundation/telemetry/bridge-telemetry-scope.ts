import { z } from 'zod';

export const bridgeTelemetryScopeSchema = z.enum(['swift', 'web', 'webkit']);

export type BridgeTelemetryScope = z.infer<typeof bridgeTelemetryScopeSchema>;
