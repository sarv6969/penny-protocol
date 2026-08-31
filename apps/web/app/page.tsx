import Link from "next/link";
import {
  PENNY_DECIMALS,
  PENNY_TOTAL_SUPPLY,
  PROTOCOL_FEE_BPS,
  ELIGIBLE_BALANCE_THRESHOLD,
  BASKET_TICKERS,
} from "@penny/sdk";

const GITHUB_URL = "https://github.com/sarv6969/penny-protocol";

const BASKET = [
  { ticker: "TE", name: "T1 Energy", theme: "U.S. solar manufacturing" },
  { ticker: "POET", name: "POET Technologies", theme: "AI photonics & interconnects" },
  { ticker: "NNE", name: "NANO Nuclear Energy", theme: "Microreactors & advanced nuclear" },
  { ticker: "WYFI", name: "WhiteFiber", theme: "AI / HPC data centres" },
  { ticker: "RCAT", name: "Red Cat", theme: "Defence drones" },
] as const;

// Clearly-labelled DEMO numbers for the hero dashboard card (no live protocol yet).
const DEMO = {
  distributed: "$0.00",
  feesCollected: "0.00 ETH",
  wallets: "—",
  rows: [
    { t: "TE", d: "+0.00" },
    { t: "POET", d: "+0.00" },
    { t: "NNE", d: "+0.00" },
    { t: "WYFI", d: "+0.00" },
    { t: "RCAT", d: "+0.00" },
  ],
};

function fmt(n: bigint): string {
  return (n / 10n ** BigInt(PENNY_DECIMALS))
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

export default function Landing() {
  const supply = fmt(PENNY_TOTAL_SUPPLY);
  const threshold = fmt(ELIGIBLE_BALANCE_THRESHOLD);
  const feePct = (PROTOCOL_FEE_BPS / 100).toFixed(0);

  return (
    <main className="ix">
      {/* ---------------------------------------------------------------- nav */}
      <nav className="ix-nav">
        <div className="ix-nav-in">
          <span className="ix-brand">
            <span className="ix-brand-sq" /> PENNY&nbsp;STOCKS
          </span>
          <div className="ix-nav-links">
            <a href="#how">HOW IT WORKS</a>
            <a href="#stocks">BASKET</a>
            <a href="#distributions">DISTRIBUTIONS</a>
            <Link href="/status">STATUS</Link>
            <a href={GITHUB_URL} target="_blank" rel="noreferrer">
              DOCS
            </a>
          </div>
          <a
            className="ix-connect"
            href={GITHUB_URL}
            target="_blank"
            rel="noreferrer"
          >
            GITHUB
          </a>
        </div>
      </nav>

      {/* --------------------------------------------------------------- hero */}
      <section className="ix-hero">
        <div className="ix-hero-in">
          <div className="ix-hero-copy">
            <h1>
              Hold $PENNY.
              <br />
              Earn stock rewards.
            </h1>
            <p>
              A {feePct}% WETH fee on trades funds Stock&nbsp;Token
              distributions to eligible holders — delivered automatically,
              every epoch.
            </p>
            <div className="ix-hero-cta">
              <a
                className="ix-btn ix-btn-dark"
                href={GITHUB_URL}
                target="_blank"
                rel="noreferrer"
              >
                READ THE CODE&nbsp;→
              </a>
              <a className="ix-btn ix-btn-lite" href="#how">
                HOW IT WORKS
              </a>
            </div>
            <span className="ix-hero-pill">
              PRE-LAUNCH — TRADING NOT YET LIVE
            </span>
          </div>

          {/* floating dashboard card */}
          <div className="ix-card">
            <div className="ix-card-head">
              <span className="ix-brand-sq dark" /> PENNY STOCKS
              <span className="ix-demo">DEMO</span>
            </div>
            <div className="ix-card-big">
              <div className="ix-lab">TOTAL VALUE DISTRIBUTED</div>
              <div className="ix-big">{DEMO.distributed}</div>
            </div>
            <div className="ix-card-duo">
              <div>
                <div className="ix-lab">FEES COLLECTED</div>
                <div className="ix-mid">{DEMO.feesCollected}</div>
              </div>
              <div>
                <div className="ix-lab">ELIGIBLE WALLETS</div>
                <div className="ix-mid">{DEMO.wallets}</div>
              </div>
            </div>
            <div className="ix-card-dist">
              <div className="ix-lab">FIRST DISTRIBUTION — AFTER LAUNCH</div>
              <div className="ix-dist-rows">
                {DEMO.rows.map((r) => (
                  <span className="ix-chip" key={r.t}>
                    <b>{r.t}</b> {r.d}
                  </span>
                ))}
              </div>
            </div>
            <div className="ix-card-note">
              Sample layout with zeroed values. Live contract reads replace
              this at launch.
            </div>
          </div>
        </div>
      </section>

      {/* ------------------------------------------------------------ metrics */}
      <section className="ix-metrics">
        <div className="ix-kicker">/ LOCKED PARAMETERS /</div>
        <h2>
          Protocol parameters.
          <br />
          Fixed in code, verified in the repo.
        </h2>
        <div className="ix-metric-row">
          <div className="ix-metric">
            <div className="ix-metric-v">{feePct}%</div>
            <div className="ix-metric-l">FEE ON TRADES</div>
            <p>Immutable WETH fee, both directions. 100% buys the basket.</p>
          </div>
          <div className="ix-metric">
            <div className="ix-metric-v">{supply.split(",")[0]}B</div>
            <div className="ix-metric-l">FIXED SUPPLY</div>
            <p>Minted once. No mint function, no tax, no blacklist.</p>
          </div>
          <div className="ix-metric">
            <div className="ix-metric-v">{threshold}</div>
            <div className="ix-metric-l">$PENNY THRESHOLD</div>
            <p>Held at snapshot = eligible for pro-rata distributions.</p>
          </div>
          <div className="ix-metric">
            <div className="ix-metric-v">{BASKET_TICKERS.length}</div>
            <div className="ix-metric-l">CONSTITUENTS</div>
            <p>Equal weight. Rotates via public 7-day timelock.</p>
          </div>
        </div>
        <div className="ix-center">
          <Link className="ix-btn ix-btn-lite" href="/status">
            VIEW PROTOCOL STATUS&nbsp;→
          </Link>
        </div>
      </section>

      {/* -------------------------------------------------------------- stocks */}
      <section id="stocks" className="ix-stocks">
        <div className="ix-stocks-head">
          <h2>Supported stocks</h2>
          <p className="ix-right-note">
            Treasury WETH buys each supported Stock Token in equal parts.
            Prices come from official Chainlink feeds at execution.
          </p>
        </div>
        <div className="ix-stock-grid">
          {BASKET.map((b) => (
            <div className="ix-stock" key={b.ticker}>
              <div className="ix-stock-top">
                <span className="ix-stock-logo">{b.ticker.slice(0, 2)}</span>
                <div>
                  <div className="ix-stock-ticker">{b.ticker}</div>
                  <div className="ix-stock-name">{b.name}</div>
                </div>
              </div>
              <div className="ix-stock-foot">
                <div>
                  <div className="ix-lab">THEME</div>
                  <div className="ix-stock-theme">{b.theme}</div>
                </div>
                <span className="ix-stock-w">20%</span>
              </div>
            </div>
          ))}
          <div className="ix-stock ix-stock-more">
            <div className="ix-lab">BASKET ROTATION</div>
            <div className="ix-stock-more-t">Constituents rotate</div>
            <p>
              Stocks join or leave through a public 7-day timelock with onchain
              reasons — rewards already earned never change.
            </p>
            <a href={GITHUB_URL} target="_blank" rel="noreferrer">
              VIEW POLICY →
            </a>
          </div>
        </div>
      </section>

      {/* ---------------------------------------------------------------- how */}
      <section id="how" className="ix-how">
        <h2>How it works</h2>
        <div className="ix-how-grid">
          <div className="ix-how-card">
            <div className="ix-how-n">01</div>
            <h3>Trade</h3>
            <p>
              Swap ETH ↔ $PENNY in a dedicated Uniswap v4 pool on Robinhood
              Chain. The {feePct}% fee is collected in WETH by an immutable
              hook — both directions, capped in code.
            </p>
          </div>
          <div className="ix-how-card">
            <div className="ix-how-n">02</div>
            <h3>Accumulate</h3>
            <p>
              Collected fees buy the five Stock Tokens in equal parts, guarded
              by Chainlink prices and fail-closed market-session rules. Every
              purchase is onchain.
            </p>
          </div>
          <div className="ix-how-card">
            <div className="ix-how-n">03</div>
            <h3>Get paid</h3>
            <p>
              Hold {threshold}+ $PENNY at the snapshot, pass the one-time
              eligibility check, opt in with one signature — rewards arrive in
              your wallet every epoch. No claiming. No gas.
            </p>
          </div>
        </div>
      </section>

      {/* -------------------------------------------------------- distributions */}
      <section id="distributions" className="ix-dists">
        <div className="ix-dists-head">
          <h2>Recent distributions</h2>
          <span className="ix-demo">NONE YET — PRE-LAUNCH</span>
        </div>
        <div className="ix-table">
          <div className="ix-tr ix-th">
            <span>TIME</span>
            <span>STOCKS DISTRIBUTED</span>
            <span>WALLETS</span>
            <span>TX</span>
          </div>
          <div className="ix-empty">
            Distributions begin after launch. Every epoch will appear here with
            its Merkle root, per-stock amounts, and Blockscout link —
            reproducible from public data.
          </div>
        </div>
        <div className="ix-trust-row">
          <div className="ix-trust">
            <h3>No admin games</h3>
            <p>
              Custody routes wire once and can never be redirected — even by
              owners. The fee can never exceed {feePct}%.
            </p>
          </div>
          <div className="ix-trust">
            <h3>Rewards can&apos;t be taken back</h3>
            <p>
              Roots activate after a public challenge window; entitlements
              never decrease; completed claims can&apos;t be clawed back.
            </p>
          </div>
          <div className="ix-trust">
            <h3>Honest about status</h3>
            <p>
              Unaudited. No legal signoff yet. Mainnet deploy is blocked in
              code until audit, counsel, and liquidity gates close.
            </p>
          </div>
        </div>
      </section>

      {/* -------------------------------------------------------------- bottom */}
      <section className="ix-bottom">
        <span>Stock Token rewards for eligible $PENNY holders.</span>
        <a
          className="ix-btn ix-btn-dark"
          href={GITHUB_URL}
          target="_blank"
          rel="noreferrer"
        >
          READ THE CODE&nbsp;→
        </a>
      </section>

      <footer className="ix-foot">
        <p>
          Informational only; not financial, legal, tax, or investment advice.
          $PENNY is not redeemable for the basket and does not represent
          ownership of Stock Tokens or underlying shares. Distributions are
          tokenised instruments providing economic exposure — not brokerage
          shares — and do not include voting rights or dividends. Rewards
          depend on trading volume and can pause; nothing here promises
          returns. Unavailable in restricted jurisdictions including the
          United States. Project is pre-launch and unaudited.
        </p>
        <p>
          <a href={GITHUB_URL} target="_blank" rel="noreferrer">
            GitHub
          </a>{" "}
          · <Link href="/status">Status</Link> · ©{" "}
          {new Date().getFullYear()} Penny Protocol
        </p>
      </footer>
    </main>
  );
}
