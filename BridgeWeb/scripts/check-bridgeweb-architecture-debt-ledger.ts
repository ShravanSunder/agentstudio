import { readFile } from 'node:fs/promises';

// Known debt for BridgeWeb architecture rules, frozen by count per rule and file
// in the same TSV format and with the same reconciliation as the Swift
// architecture lint's `architecture-debt-ledger.tsv`: a header
// `rule_id<TAB>path<TAB>count`, repository-relative paths, counts of at least 1,
// rows sorted by rule then path. A file may keep exactly its recorded count; a
// new site, a higher count, a lower count, a paid-off row and a row for a
// missing file all fail until the ledger is updated to match.

export interface DebtLedgerEntry<TRuleId extends string> {
	readonly count: number;
	readonly line: number;
	readonly path: string;
	readonly ruleId: TRuleId;
}

export interface DebtLedger<TRuleId extends string> {
	readonly entries: readonly DebtLedgerEntry<TRuleId>[];
	readonly sourcePath: string;
}

export interface DebtLedgerSite<TRuleId extends string> {
	readonly column: number;
	readonly line: number;
	readonly message: string;
	readonly relativePath: string;
	readonly ruleId: TRuleId;
}

export interface ReconcileDebtLedgerProps<TRuleId extends string> {
	readonly ledger: DebtLedger<TRuleId>;
	// Package-relative paths of every file this run linted.
	readonly lintedPaths: ReadonlySet<string>;
	// The package's path from the repository root, e.g. `BridgeWeb/`.
	readonly repositoryPathPrefix: string;
	readonly sites: readonly DebtLedgerSite<TRuleId>[];
}

const ledgerHeader = 'rule_id\tpath\tcount';

export async function loadDebtLedger<TRuleId extends string>(props: {
	readonly filePath: string;
	readonly isLedgerRuleId: (value: string) => value is TRuleId;
	readonly sourcePath: string;
}): Promise<DebtLedger<TRuleId>> {
	let contents: string;
	try {
		contents = await readFile(props.filePath, 'utf8');
	} catch (error: unknown) {
		if (error instanceof Error && 'code' in error && error.code === 'ENOENT') {
			return { entries: [], sourcePath: props.sourcePath };
		}
		throw error;
	}
	return parseDebtLedger({ ...props, contents });
}

export function parseDebtLedger<TRuleId extends string>(props: {
	readonly contents: string;
	readonly isLedgerRuleId: (value: string) => value is TRuleId;
	readonly sourcePath: string;
}): DebtLedger<TRuleId> {
	const lines = props.contents.split('\n');
	if (lines.at(-1) === '') lines.pop();
	const malformed = (line: number, reason: string): Error =>
		new Error(`${props.sourcePath}:${line}: malformed debt ledger: ${reason}`);
	if (lines[0] !== ledgerHeader) {
		throw malformed(1, 'first line must be the header "rule_id<TAB>path<TAB>count"');
	}
	const entries: DebtLedgerEntry<TRuleId>[] = [];
	for (const [index, text] of lines.entries()) {
		if (index === 0) continue;
		const line = index + 1;
		const fields = text.split('\t');
		const [ruleId, path, countText] = fields;
		if (fields.length !== 3 || ruleId === undefined || path === undefined) {
			throw malformed(
				line,
				`expected 3 tab-separated fields (rule_id, path, count), found ${fields.length}`,
			);
		}
		if (ruleId === '' || path === '' || path.startsWith('/') || path.includes('..')) {
			throw malformed(line, 'rule_id and a repository-relative path are required');
		}
		if (!props.isLedgerRuleId(ruleId)) {
			throw malformed(line, `rule_id ${ruleId} does not keep a debt ledger`);
		}
		const count = Number(countText);
		if (!Number.isInteger(count) || count < 1) {
			throw malformed(
				line,
				'count must be a whole number of at least 1; remove the row instead of writing 0',
			);
		}
		const previous = entries.at(-1);
		if (previous !== undefined && compareLedgerKeys(previous, { path, ruleId }) >= 0) {
			throw malformed(
				line,
				previous.ruleId === ruleId && previous.path === path
					? `duplicate row for ${ruleId} ${path}`
					: 'rows must be sorted by rule_id, then path',
			);
		}
		entries.push({ count, line, path, ruleId });
	}
	return { entries, sourcePath: props.sourcePath };
}

// Returns the sites and ledger diagnostics that fail this run. `ledgerRowSite`
// builds a diagnostic for a ledger row itself (a row naming a missing file).
export function reconcileDebtLedger<TRuleId extends string>(
	props: ReconcileDebtLedgerProps<TRuleId>,
	ledgerRowSite: (entry: DebtLedgerEntry<TRuleId>, message: string) => DebtLedgerSite<TRuleId>,
): readonly DebtLedgerSite<TRuleId>[] {
	const entryByKey = new Map(
		props.ledger.entries.map((entry): [string, DebtLedgerEntry<TRuleId>] => [
			ledgerKey(entry.ruleId, entry.path),
			entry,
		]),
	);
	const sitesByKey = new Map<string, DebtLedgerSite<TRuleId>[]>();
	for (const site of props.sites) {
		const key = ledgerKey(site.ruleId, `${props.repositoryPathPrefix}${site.relativePath}`);
		sitesByKey.set(key, [...(sitesByKey.get(key) ?? []), site]);
	}

	const reconciled: DebtLedgerSite<TRuleId>[] = [];
	for (const [key, sites] of sitesByKey) {
		const entry = entryByKey.get(key);
		const firstSite = sites[0];
		if (entry === undefined || firstSite === undefined) {
			reconciled.push(...sites);
			continue;
		}
		if (sites.length > entry.count) {
			reconciled.push(
				...sites.map(
					(site): DebtLedgerSite<TRuleId> => ({
						...site,
						message: `${site.message} [count ${sites.length} exceeds ${entry.count} permitted by ${props.ledger.sourcePath}]`,
					}),
				),
			);
		} else if (sites.length < entry.count) {
			reconciled.push({
				...firstSite,
				column: 1,
				line: 1,
				message: `Debt ledger permits ${entry.count} here but ${sites.length} remain; lower the row to ${sites.length} in ${props.ledger.sourcePath}`,
			});
		}
	}

	for (const entry of props.ledger.entries) {
		if (sitesByKey.has(ledgerKey(entry.ruleId, entry.path))) continue;
		const packagePath = entry.path.startsWith(props.repositoryPathPrefix)
			? entry.path.slice(props.repositoryPathPrefix.length)
			: null;
		if (packagePath !== null && props.lintedPaths.has(packagePath)) {
			reconciled.push({
				...ledgerRowSite(
					entry,
					`Debt ledger permits ${entry.count} here but none remain; remove the row from ${props.ledger.sourcePath}`,
				),
				relativePath: packagePath,
				column: 1,
				line: 1,
			});
		} else {
			reconciled.push(
				ledgerRowSite(
					entry,
					`Debt ledger row names ${entry.path}, which no longer exists or is not linted; remove the row`,
				),
			);
		}
	}
	return reconciled;
}

function ledgerKey(ruleId: string, repositoryPath: string): string {
	return `${ruleId}\t${repositoryPath}`;
}

function compareLedgerKeys(
	left: { readonly path: string; readonly ruleId: string },
	right: { readonly path: string; readonly ruleId: string },
): number {
	if (left.ruleId !== right.ruleId) return left.ruleId < right.ruleId ? -1 : 1;
	if (left.path === right.path) return 0;
	return left.path < right.path ? -1 : 1;
}
