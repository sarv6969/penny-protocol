import assert from "node:assert/strict";
import { test } from "node:test";

import { buildManifest, canonicalize } from "../src/manifest.js";
import type { ManifestMeta } from "../src/manifest.js";

function meta(generatedAt: string): ManifestMeta {
  return { generatedAt, softwareVersion: "8.0.0", commit: "abc123" };
}

const payload = (total: string) => ({
  schemaVersion: "1.0.0",
  chainId: 4663,
  snapshot: { blockNumber: 6, blockHash: "0xdd" },
  totals: { "0xaa": total },
  nested: { b: [3n, 1n, 2n], a: { z: true, x: null } },
  root: "0xee",
});

test("canonicalize sorts keys recursively and emits compact JSON", () => {
  const out = canonicalize({ z: 1, a: { y: null, b: [2n, 1n] } });
  assert.equal(out, '{"a":{"b":["2","1"],"y":null},"z":1}');
});

test("buildManifest reports identical content hash across builds differing only in generatedAt", () => {
  const m1 = buildManifest(meta("2026-01-01T00:00:00Z"), payload("100"));
  const m2 = buildManifest(meta("2026-12-31T23:59:59Z"), payload("100"));
  assert.equal(m1.contentHash, m2.contentHash, "transient meta must not enter the hash");
  assert.equal(m1.canonicalJson, m2.canonicalJson);
});

test("buildManifest changes content hash when inputs change", () => {
  const m1 = buildManifest(meta("t"), payload("100"));
  const m2 = buildManifest(meta("t"), payload("101"));
  assert.notEqual(m1.contentHash, m2.contentHash);
});

test("manifest meta is not part of the hashed payload", () => {
  const m = buildManifest(meta("t"), payload("100"));
  assert.equal(m.manifest.meta, m.meta);
  assert.equal(typeof m.manifest.contentHash, "string");
});