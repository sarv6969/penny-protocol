import Link from "next/link";
import {
  PENNY_DECIMALS,
  PENNY_TOTAL_SUPPLY,
  PROTOCOL_FEE_BPS,
  ELIGIBLE_BALANCE_THRESHOLD,
  BASKET_TICKERS,
} from "@penny/sdk";
import { loadSampleManifest } from "./lib/manifest";
import { ClaimLookup } from "./claim-lookup";

export default function Home() {
  const manifest = loadSampleManifest();
  const supplyDisplay = (PENNY_TOTAL_SUPPLY / 10n ** BigInt(PENNY_DECIMALS))
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  const thresholdDisplay = (
    ELIGIBLE_BALANCE_THRESHOLD /
    10n ** BigInt(PENNY_DECIMALS)
  )
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ",");

  return (
    <main className="wrap">
      <header className="site">
        <h1>Penny Stocks</h1>
        <p className="sub">CLAIM STATUS — sample data for UI preview only.</p>
      </header>

      <section>
        <h2>Protocol summary (locked economics, D004)</h2>
        <div className="grid">
          <div className="stat">
            <div className="label">PENNY supply</div>
            <div className="value">
              {supplyDisplay}{" "}
              <span className="dim">({PENNY_DECIMALS} decimals)</span>
            </div>
          </div>
          <div className="stat">
            <div className="label">Protocol fee</div>
            <div className="value">
              {PROTOCOL_FEE_BPS} bps{" "}
              <span className="dim">WETH, both directions</span>
            </div>
          </div>
          <div className="stat">
            <div className="label">Eligibility threshold</div>
            <div className="value">{thresholdDisplay} PENNY</div>
          </div>
          <div className="stat">
            <div className="label">Founding Stock Tokens</div>
            <div className="value">{BASKET_TICKERS.join(", ")}</div>
          </div>
        </div>
        <p className="dim">
          PENNY is a fixed-supply rewards token, not redeemable for Stock Tokens
          and not an ownership interest in any underlying shares. Stock Token
          rewards provide economic exposure only. See FAQ/compliance notes
          below.
        </p>
      </section>

      <section>
        <h2>Epoch status</h2>
        <p className="dim">
          Snapshot of <code>manifest.sample.json</code> (live manifests are
          served by the indexer; this file is a fixed sample for the UI).
        </p>
        <div className="grid">
          <div className="stat">
            <div className="label">Epoch</div>
            <div className="value">#{manifest.epochIndex}</div>
          </div>
          <div className="stat">
            <div className="label">Snapshot block</div>
            <div className="value">{manifest.snapshotBlock}</div>
          </div>
          <div className="stat">
            <div className="label">Root</div>
            <div className="value">
              <code>{manifest.root.slice(0, 18)}…</code>
            </div>
          </div>
          <div className="stat">
            <div className="label">Generated</div>
            <div className="value">{manifest.generatedAt.slice(0, 10)}</div>
          </div>
        </div>

        <div className="card">
          <h3>Reward assets in this epoch</h3>
          <ul className="plain">
            {manifest.assets.map((a) => (
              <li key={a.ticker}>
                <strong>{a.ticker}</strong> —{" "}
                <span className="dim">{a.name}</span> ({a.decimals} decimals)
              </li>
            ))}
          </ul>
          <p className="dim">
            Placeholder token addresses (clearly labeled, not deployed):{" "}
            {manifest.assets
              .map((a) => `${a.ticker} ${a.placeholderAddress}`)
              .join(" · ")}
          </p>
        </div>

        <div className="notice">
          {manifest.note}. Root and content hash values above are
          zero-placeholders; live manifests carry real values.
        </div>
      </section>

      <section>
        <h2>How rewards reach your wallet</h2>
        <ol className="steps">
          <li>
            <strong>Eligibility</strong> — hold at least {thresholdDisplay}{" "}
            PENNY at the snapshot block and pass the jurisdiction check to be
            included in an epoch.
          </li>
          <li>
            <strong>Scoped attestation</strong> — the attestation service signs
            an expiring eligibility attestation scoped to this wallet, epoch
            index, root, chain, and registry, so it cannot be replayed
            anywhere else.
          </li>
          <li>
            <strong>Auto-delivery (default)</strong> — opt in once with a
            single signature and Stock Token rewards are delivered to your
            wallet automatically each epoch. No claiming, no gas. Delivery can
            only ever land in your own wallet, and you can opt out anytime.
          </li>
          <li>
            <strong>Self-claim (fallback)</strong> — if you prefer not to opt
            in, one transaction settles all unclaimed epochs at once
            (exactly-once catch-up).
          </li>
        </ol>
        <p className="dim">
          Auto-delivery is relayed on your behalf but is structurally
          non-custodial: the onchain leaf binds rewards to the entitled wallet,
          so no relayer can redirect them. Deliveries pause for wallets whose
          eligibility attestation has expired or been revoked.
        </p>
        <p className="dim">
          Sample eligible wallets in this manifest:{" "}
          {manifest.claims.filter((c) => c.eligible).length} of{" "}
          {manifest.claims.length}.
        </p>

        <h3>Look up a sample wallet</h3>
        <ClaimLookup claims={manifest.claims} />
        <p className="dim">
          Addresses above are sample data only. No wallet is connected and no
          keys are shipped by this UI.
        </p>
      </section>

      <section>
        <h2>Scoped claim path</h2>
        <p>
          Per-epoch claim routes are served statically. Open{" "}
          <Link href={`/claim/${manifest.epochIndex}`}>
            epoch #{manifest.epochIndex} claim
          </Link>{" "}
          to preview the scoped claim view for this sample.
        </p>
      </section>

      <footer className="site">
        <p>
          This interface is a static, stateless status preview. It ships no
          signing keys, connects to no wallet, and stores no private data.
        </p>
        <p>
          Nothing on this page is legal, tax, or financial advice. This project
          has not obtained legal approval for any jurisdiction and is not
          audited. Consult counsel.
        </p>
      </footer>
    </main>
  );
}
