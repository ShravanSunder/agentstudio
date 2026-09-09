import { pathToFileURL } from "node:url";

import { campaignRequestDatasetName } from "../src/campaign-attribution/campaign-request-attribution.ts";

export const campaignRequestQueryGroups = ["total", "path", "channel", "creative"] as const;
export type CampaignRequestQueryGroup = (typeof campaignRequestQueryGroups)[number];

const isCampaignRequestQueryGroup = (value: string): value is CampaignRequestQueryGroup =>
  campaignRequestQueryGroups.some((candidate) => candidate === value);

interface CampaignRequestQueryInput {
  readonly from: string;
  readonly to: string;
  readonly group: CampaignRequestQueryGroup;
}

const isoTimestampPattern = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{3})?Z$/;
const maximumQueryWindowMilliseconds = 93 * 24 * 60 * 60 * 1000;

const assertBoundedTimeWindow = (from: string, to: string): void => {
  if (!isoTimestampPattern.test(from) || !isoTimestampPattern.test(to)) {
    throw new Error("Campaign analytics times must be explicit UTC ISO timestamps");
  }

  const fromMilliseconds = Date.parse(from);
  const toMilliseconds = Date.parse(to);
  if (
    !Number.isFinite(fromMilliseconds) ||
    !Number.isFinite(toMilliseconds) ||
    fromMilliseconds >= toMilliseconds ||
    toMilliseconds - fromMilliseconds > maximumQueryWindowMilliseconds
  ) {
    throw new Error("Campaign analytics time window must be positive and at most 93 days");
  }
};

const formatCloudflareDateTime = (isoTimestamp: string): string =>
  new Date(isoTimestamp).toISOString().slice(0, 19).replace("T", " ");

const selectAndGroupByByQueryGroup = {
  total: { groupBy: "", select: "" },
  path: { groupBy: "GROUP BY path", select: "index1 AS path," },
  channel: { groupBy: "GROUP BY channel", select: "blob2 AS channel," },
  creative: {
    groupBy: "GROUP BY route_kind, channel, campaign, creative, variant, placement",
    select:
      "blob1 AS route_kind, blob2 AS channel, blob3 AS campaign, blob4 AS creative, blob5 AS variant, blob6 AS placement,",
  },
} as const satisfies Record<
  CampaignRequestQueryGroup,
  { readonly groupBy: string; readonly select: string }
>;

export const buildCampaignRequestQuery = (input: CampaignRequestQueryInput): string => {
  assertBoundedTimeWindow(input.from, input.to);
  const projection = selectAndGroupByByQueryGroup[input.group];
  const fromDateTime = formatCloudflareDateTime(input.from);
  const toDateTime = formatCloudflareDateTime(input.to);

  return [
    `SELECT ${projection.select}`,
    '  sum(_sample_interval) AS "campaign_path_requests"',
    `FROM ${campaignRequestDatasetName}`,
    `WHERE timestamp >= toDateTime('${fromDateTime}', 'UTC')`,
    `  AND timestamp < toDateTime('${toDateTime}', 'UTC')`,
    projection.groupBy,
    "ORDER BY campaign_path_requests DESC",
    "FORMAT JSON",
  ]
    .filter((line) => line.length > 0)
    .join("\n");
};

const parseArguments = (argumentsList: readonly string[]): CampaignRequestQueryInput => {
  const argumentMap = new Map<string, string>();
  for (let argumentIndex = 0; argumentIndex < argumentsList.length; argumentIndex += 2) {
    const name = argumentsList[argumentIndex];
    const value = argumentsList[argumentIndex + 1];
    if (name === undefined || value === undefined || !name.startsWith("--")) {
      throw new Error("Expected --from, --to, and --group campaign analytics arguments");
    }
    argumentMap.set(name, value);
  }

  const from = argumentMap.get("--from");
  const to = argumentMap.get("--to");
  const group = argumentMap.get("--group");
  if (
    from === undefined ||
    to === undefined ||
    group === undefined ||
    !isCampaignRequestQueryGroup(group)
  ) {
    throw new Error("Expected --from, --to, and a valid --group campaign analytics argument");
  }

  return { from, group, to };
};

export const executeCampaignRequestQuery = async (
  input: CampaignRequestQueryInput,
  accountIdentifier: string,
  apiToken: string,
  request: typeof fetch = fetch,
): Promise<unknown> => {
  const response = await request(
    `https://api.cloudflare.com/client/v4/accounts/${encodeURIComponent(accountIdentifier)}/analytics_engine/sql`,
    {
      body: buildCampaignRequestQuery(input),
      headers: { Authorization: `Bearer ${apiToken}`, "Content-Type": "text/plain" },
      method: "POST",
    },
  );

  if (!response.ok) {
    throw new Error(`Cloudflare campaign analytics query failed with HTTP ${response.status}`);
  }
  const result: unknown = await response.json();
  return result;
};

const run = async (): Promise<void> => {
  const accountIdentifier = process.env["CLOUDFLARE_ACCOUNT_ID"];
  const apiToken = process.env["CLOUDFLARE_API_TOKEN"];
  if (accountIdentifier === undefined || apiToken === undefined) {
    throw new Error(
      "Campaign analytics requires Cloudflare account and read-token environment values",
    );
  }

  const result = await executeCampaignRequestQuery(
    parseArguments(process.argv.slice(2)),
    accountIdentifier,
    apiToken,
  );
  process.stdout.write(`${JSON.stringify(result, undefined, 2)}\n`);
};

if (process.argv[1] !== undefined && import.meta.url === pathToFileURL(process.argv[1]).href) {
  await run().catch((): never => {
    process.stderr.write(
      "Campaign analytics query failed. Verify the time window, network access, and private credentials.\n",
    );
    process.exit(1);
  });
}
