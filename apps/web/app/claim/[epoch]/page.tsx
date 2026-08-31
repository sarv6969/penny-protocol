import Link from "next/link";
import {
  PENNY_DECIMALS,
  ELIGIBLE_BALANCE_THRESHOLD,
  PROTOCOL_FEE_BPS,
  BASKET_TICKERS,
} from "@penny/sdk";
import { loadSampleManifest } from "../../lib/manifest";

export const dynamicParams = false;

export function generateStaticParams() {
  const manifest = loadSampleManifest();
  return [{ epoch: String(manifest.epochIndex) }];
}

export function generateMetadata({
  params,
}: {
  params: Promise<{ epoch: string }>;
}) {
  return params.then(({ epoch }) => ({
    title: `Epoch ${epoch} claim — Penny Stocks`,
  }));
}

export default async function ClaimPage({
  params,
}: {
  params: Promise<{ epoch: string }>;
}) {
  const { epoch: requested } = await params;
  const manifest = loadSampleManifest();
  const isSampleEpoch = String(manifest.epochIndex) === requested;
  const thresholdDisplay = (
    ELIGIBLE_BALANCE_THRESHOLD /
    10n ** BigInt(PENNY_DECIMALS)
  )
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ",");

  const eligible = manifest.claims.filter((c) => c.eligible);

  return (
    <main className="wrap">
      <header className="site">
        <h1>Penny Stocks</h1>
        <p className="sub">
          Epoch #{requested} scoped claim path{" "}
          {isSampleEpoch ? "" : "(no sample manifest — sample preview below)"}
        </p>
      </header>

      <section>
        <h2>Epoch #{requested} — scoped claim</h2>
        {isSampleEpoch ? (
          <>
            <div className="grid">
              <div className="stat">
                <div className="label">Snapshot block</div>
                <div className="value">{manifest.snapshotBlock}</div>
              </div>
              <div className="stat">
                <div className="label">Reward assets</div>
                <div className="value">{manifest.assets.length}</div>
              </div>
              <div className="stat">
                <div className="label">Eligible sample wallets</div>
                <div className="value">{eligible.length}</div>
              </div>
              <div className="stat">
                <div className="label">Protocol fee</div>
                <div className="value">{PROTOCOL_FEE_BPS} bps WETH</div>
              </div>
            </div>

            <div className="card">
              <h3>Scope of this claim</h3>
              <ul className="plain">
                <li>
                  Eligibility: hold ≥ {thresholdDisplay} PENNY at the snapshot
                  block.
                </li>
                <li>
                  Attestation: signed and scoped to (wallet, epoch #
                  {manifest.epochIndex}, root {manifest.root.slice(0, 18)}…).
                </li>
                <li>
                  Settlement: single-transaction catch-up across any unclaimed
                  epochs of assets {BASKET_TICKERS.join(", ")}.
                </li>
              </ul>
            </div>

            <div className="card">
              <h3>Sample eligible wallets</h3>
              <ul className="plain">
                {eligible.map((c) => (
                  <li key={c.wallet}>
                    <code>{c.wallet}</code> —{" "}
                    {c.cumulative
                      ? Object.keys(c.cumulative).length + " assets accruing"
                      : "eligible"}
                  </li>
                ))}
              </ul>
            </div>

            <pre className="sample">
              {JSON.stringify(
                {
                  epochIndex: manifest.epochIndex,
                  root: manifest.root,
                  snapshotBlock: manifest.snapshotBlock,
                  generatedAt: manifest.generatedAt,
                  contentHash: manifest.contentHash,
                  note: manifest.note,
                },
                null,
                2,
              )}
            </pre>
            <p className="dim">
              Placeholder addresses only — nothing here is a live or deployed
              contract.
            </p>
          </>
        ) : (
          <div className="notice">
            No sample manifest exists for epoch #{requested}. This path is
            exported only for epochs present in the sample data.
          </div>
        )}
      </section>

      <footer className="site">
        <p>
          <Link href="/">Back to Penny Stocks</Link> — static status preview; no
          signing keys, no wallet connection.
        </p>
        <p>
          Not legal, tax, or financial advice. Not audited. Consult counsel.
        </p>
      </footer>
    </main>
  );
}
