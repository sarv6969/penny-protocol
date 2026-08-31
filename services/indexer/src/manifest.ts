import { keccak256, toHex, type Hex } from "viem";

/**
 * Bit-for-bit reproducible epoch manifest (ADR 0003, D029).
 *
 * `canonicalize` sorts every object key recursively and emits zero-whitespace JSON with
 * bigints as decimal strings, so two clean builds over identical inputs are byte-identical.
 * `contentHash` is keccak256 over the canonical deterministic `payload`; transient fields
 * like `generatedAt` live in `meta` and never enter the hash.
 */
export function canonicalize(value: unknown): string {
  if (value === null) return "null";
  switch (typeof value) {
    case "bigint":
      return JSON.stringify(value.toString());
    case "string":
      return JSON.stringify(value);
    case "number":
    case "boolean":
      return JSON.stringify(value);
    case "object": {
      if (Array.isArray(value)) return `[${value.map(canonicalize).join(",")}]`;
      const keys = Object.keys(value).sort();
      return `{${keys.map((k) => `${JSON.stringify(k)}:${canonicalize((value as Record<string, unknown>)[k])}`).join(",")}}`;
    }
    default:
      throw new Error(`cannot canonicalize ${typeof value}`);
  }
}

export interface ManifestMeta {
  generatedAt: string;
  softwareVersion: string;
  commit: string | undefined;
}

export interface ManifestBundle {
  meta: ManifestMeta;
  payload: unknown;
  manifest: Record<string, unknown>;
  canonicalJson: string;
  contentHash: Hex;
}

export function buildManifest(meta: ManifestMeta, payload: unknown): ManifestBundle {
  const canonicalJson = canonicalize(payload);
  const contentHash = keccak256(toHex(canonicalJson));
  const manifest = { meta, payload, contentHash };
  return { meta, payload, manifest, canonicalJson, contentHash };
}