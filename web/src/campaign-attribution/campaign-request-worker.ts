import {
  createCampaignRequestDataPoint,
  isCampaignRequestEligible,
  resolveCampaignRequestRoute,
  type CampaignRequestDataPoint,
} from "./campaign-request-attribution";

interface CampaignRequestAssets {
  readonly fetch: (request: Request) => Promise<Response>;
}

interface CampaignRequestAnalytics {
  readonly writeDataPoint: (dataPoint: CampaignRequestDataPoint) => void;
}

export interface CampaignRequestWorkerEnvironment {
  readonly ASSETS: CampaignRequestAssets;
  readonly ANALYTICS: CampaignRequestAnalytics;
}

const writeAnalyticsBestEffort = (
  analytics: CampaignRequestAnalytics,
  dataPoint: CampaignRequestDataPoint,
): void => {
  try {
    analytics.writeDataPoint(dataPoint);
  } catch {
    // Analytics is intentionally fail-open; page delivery remains authoritative.
  }
};

const handleCampaignRequest = async (
  request: Request,
  environment: CampaignRequestWorkerEnvironment,
): Promise<Response> => {
  const route = resolveCampaignRequestRoute(new URL(request.url).pathname);
  const assetResponse = await environment.ASSETS.fetch(request);

  if (isCampaignRequestEligible(request, route, assetResponse)) {
    writeAnalyticsBestEffort(environment.ANALYTICS, createCampaignRequestDataPoint(route));
  }

  return assetResponse;
};

export default {
  fetch: handleCampaignRequest,
};
