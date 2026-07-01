import { describe, expect, test, vi } from 'vitest';

import { createBridgeProtocolRegistry } from '../models/bridge-protocol-registry.js';
import { sendBridgeContentWorldRPC } from './bridge-content-world-rpc.js';

describe('bridge content-world RPC host', () => {
	const protocolRegistry = createBridgeProtocolRegistry({
		protocols: [
			{
				protocol: 'review',
				resourceKinds: ['content'],
				privilegedMethods: ['review.openStream'],
			},
			{
				protocol: 'worktree-file',
				resourceKinds: ['tree', 'file-content'],
				privilegedMethods: ['worktree-file.openStream'],
			},
		],
	});

	test('sends allowlisted protocol RPC through bridge-world internal sender only', () => {
		const postedCommandJSON: string[] = [];
		const pageWorldCommand = vi.fn();
		const host = {
			__bridgeInternal: {
				sendCommandJSON(commandJSON: string): void {
					postedCommandJSON.push(commandJSON);
				},
			},
			__bridge_command: pageWorldCommand,
		};

		const result = sendBridgeContentWorldRPC({
			command: {
				id: 'command-1',
				protocol: 'review',
				method: 'review.openStream',
				params: {
					streamId: 'stream-1',
				},
			},
			host,
			protocolRegistry,
		});

		expect(result).toEqual({ ok: true });
		expect(postedCommandJSON).toHaveLength(1);
		expect(JSON.parse(postedCommandJSON[0] ?? '{}')).toEqual({
			jsonrpc: '2.0',
			id: 'command-1',
			protocol: 'review',
			method: 'review.openStream',
			params: {
				streamId: 'stream-1',
			},
		});
		expect(pageWorldCommand).not.toHaveBeenCalled();
	});

	test('rejects unregistered protocol RPC without falling back to page-world command', () => {
		const pageWorldCommand = vi.fn();
		const bridgeWorldSender = vi.fn();
		const host = {
			__bridgeInternal: {
				sendCommandJSON: bridgeWorldSender,
			},
			__bridge_command: pageWorldCommand,
		};

		const result = sendBridgeContentWorldRPC({
			command: {
				id: 'command-2',
				protocol: 'comments',
				method: 'comments.openStream',
				params: {},
			},
			host,
			protocolRegistry,
		});

		expect(result).toEqual({ ok: false, reason: 'unregistered_protocol_method' });
		expect(bridgeWorldSender).not.toHaveBeenCalled();
		expect(pageWorldCommand).not.toHaveBeenCalled();
	});
});
