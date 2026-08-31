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

// Clearly-labelled SAMPLE values for the hero receipt (no live protocol yet).
const RECEIPT_ROWS = [
  { t: "TE", n: "T1 ENERGY" },
  { t: "POET", n: "POET TECHNOLOGIES" },
  { t: "NNE", n: "NANO NUCLEAR" },
  { t: "WYFI", n: "WHITEFIBER" },
  { t: "RCAT", n: "RED CAT" },
];

const TAPE =
  "TE ▲ · POET ▲ · NNE ▲ · WYFI ▲ · RCAT ▲ · 3% FEE → BASKET · REWARDS EVERY EPOCH · ";

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
            <span className="ix-hero-pill">
              ● PRE-LAUNCH — TRADING NOT YET LIVE
            </span>
            <h1>
              Every trade
              <br />
              feeds the basket.
              <br />
              <em>The basket pays you.</em>
            </h1>
            <p>
              $PENNY takes a {feePct}% cut of its own trading volume and spends
              it on five small-cap Stock Tokens. Hold {threshold}+ and pass the
              one-time check — your share lands in your wallet every epoch,
              automatically.
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
          </div>

          {/* trade-receipt card */}
          <div className="ix-receipt">
            <div className="ix-receipt-head">
              <span>PENNY PROTOCOL</span>
              <span className="ix-demo">SAMPLE</span>
            </div>
            <div className="ix-receipt-title">— BASKET PURCHASE ORDER —</div>
            <div className="ix-receipt-meta">
              EPOCH #001 · ROBINHOOD CHAIN · AFTER LAUNCH
            </div>
            <div className="ix-receipt-rows">
              {RECEIPT_ROWS.map((r) => (
                <div className="ix-receipt-row" key={r.t}>
                  <span className="ix-receipt-tick">{r.t}</span>
                  <span className="ix-receipt-dots" />
                  <span className="ix-receipt-name">{r.n}</span>
                  <span className="ix-receipt-w">20%</span>
                </div>
              ))}
            </div>
            <div className="ix-receipt-total">
              <span>FEE POOL DEPLOYED</span>
              <span>100%</span>
            </div>
            <div className="ix-receipt-barcode" aria-hidden>
              ║█║▌║█▌║║█║▌█║║▌║█║█▌║║▌█║
            </div>
            <div className="ix-receipt-note">
              SAMPLE RECEIPT — VALUES APPEAR AT LAUNCH. NOT REDEEMABLE. NOT
              SHARES.
            </div>
          </div>
        </div>

        {/* ticker tape */}
        <div className="ix-tape" aria-hidden>
          <div className="ix-tape-inner">
            <span>{TAPE.repeat(4)}</span>
            <span>{TAPE.repeat(4)}</span>
          </div>
        </div>
      </section>

      {/* ------------------------------------------------------------ metrics */}
      <section className="ix-metrics">
        <div className="ix-kicker">CARVED IN BYTECODE</div>
        <h2>
          Four numbers.
          <br />
          Nobody can change them — not even us.
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
          <h2>The moonshot shelf</h2>
          <p className="ix-right-note">
            Fee WETH buys every constituent in equal parts, priced by official
            Chainlink feeds at execution. Small caps only — that&apos;s the
            point.
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
            <h3>Volume becomes fuel</h3>
            <p>
              Every ETH ↔ $PENNY swap on Robinhood Chain pays a {feePct}% WETH
              fee into the treasury. The fee is enforced by an immutable
              Uniswap v4 hook — both directions, capped in code, no override.
            </p>
          </div>
          <div className="ix-how-card">
            <div className="ix-how-n">02</div>
            <h3>Fuel becomes stocks</h3>
            <p>
              The treasury spends itself on the five Stock Tokens in equal
              parts — Chainlink-priced, market-session-guarded, all-or-nothing.
              Every purchase is a public onchain event.
            </p>
          </div>
          <div className="ix-how-card">
            <div className="ix-how-n">03</div>
            <h3>Stocks become yours</h3>
            <p>
              Hold {threshold}+ $PENNY at the snapshot, pass the one-time
              eligibility check, sign once to opt in — then rewards just show
              up, every epoch. No claiming. No gas. Opt out anytime.
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
        <span>
          Don&apos;t trust the pitch. The whole machine is open source.
        </span>
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
