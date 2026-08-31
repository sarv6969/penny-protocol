export interface ManifestEntry {
  chainId: number;
  name: string;
  symbol?: string;
  decimals?: number;
  sourceUrl: string;
  verification: "docs-only" | "onchain" | "blocked";
  verifiedAtBlock?: number;
  codeHash?: string;
}

export interface AddressManifest {
  generatedAt: string;
  schemaVersion: string;
  entries: Record<string, ManifestEntry>;
}

export function entry(manifest: AddressManifest, key: string): ManifestEntry | undefined {
  return manifest.entries[key];
}

export function requireEntry(manifest: AddressManifest, key: string): ManifestEntry {
  const found = entry(manifest, key);
  if (!found) throw new Error(`manifest missing required entry: ${key}`);
  return found;
}

export function assertAllVerified(manifest: AddressManifest, keys: string[]): void {
  for (const key of keys) {
    const e = requireEntry(manifest, key);
    if (e.verification === "blocked") {
      throw new Error(`manifest entry not verified: ${key}`);
    }
  }
}