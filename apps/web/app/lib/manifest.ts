import path from "node:path";
import fs from "node:fs";

export interface SampleManifestAsset {
  ticker: string;
  name: string;
  decimals: number;
  rewardPool: string;
  placeholderAddress: string;
}

export interface SampleManifestClaim {
  wallet: string;
  eligible: boolean;
  cumulative?: Record<string, string>;
  note?: string;
}

export interface SampleManifest {
  $schema: string;
  epochIndex: number;
  root: string;
  snapshotBlock: number;
  assets: SampleManifestAsset[];
  claims: SampleManifestClaim[];
  generatedAt: string;
  contentHash: string;
  note: string;
}

export function loadSampleManifest(): SampleManifest {
  const file = path.join(process.cwd(), "public", "manifest.sample.json");
  const raw = fs.readFileSync(file, "utf8");
  return JSON.parse(raw) as SampleManifest;
}
