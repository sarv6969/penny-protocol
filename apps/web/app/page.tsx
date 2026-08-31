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
  {
    ticker: "TE",
    name: "T1 Energy",
    theme: "U.S. solar manufacturing",
  },
  {
    ticker: "POET",
    name: "POET Technologies",
    theme: "AI photonics & interconnects",
  },
  {
    ticker: "NNE",
    name: "NANO Nuclear Energy",
    theme: "Microreactors & advanced nuclear",
  },
  {
    ticker: "WYFI",
    name: "WhiteFiber",
    theme: "AI / HPC data centres",
  },
  {
    ticker: "RCAT",
    name: "Red Cat",
    theme: "Defence drones",
  },
] as const;

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
    <main className="landing">
      {/* ---------------------------------------------------------------- nav */}
      <nav className="nav">
        <div className="nav-inner">
          <span className="brand">
            <span className="brand-mark">P</span> Penny&nbsp;Protocol
          </span>
          <div className="nav-links">
            <a href="#how">How it works</a>
            <a href="#basket">Basket</a>
            <a href="#transparency">Transparency</a>
            <Link href="/status">Status</Link>
            <a
              className="btn btn-ghost"
              href={GITHUB_URL}
              target="_blank"
              rel="noreferrer"
            >
              GitHub ↗
            </a>
          </div>
        </div>
      </nav>

      {/* --------------------------------------------------------------- hero */}
      <section className="hero">
        <span className="pill">
          <span className="pill-dot" /> Pre-launch — trading not yet live
        </span>
        <h1>
          One token.
          <br />
          <span className="grad">A rotating basket of small-cap moonshots.</span>
        </h1>
        <p className="lede">
          ${"PENNY"} trades against ETH on Robinhood Chain. {feePct}% of every
          trade buys Robinhood Stock Tokens across five small-cap themes — and
          eligible holders receive their pro-rata share automatically, every
          epoch. No claiming. No gas.
        </p>
        <div className="cta-row">
          <a
            className="btn btn-primary"
            href={GITHUB_URL}
            target="_blank"
            rel="noreferrer"
          >
            Read the code on GitHub
          </a>
          <a className="btn btn-secondary" href="#how">
            How it works
          </a>
        </div>
        <p className="hero-fine">
          PENNY is not redeemable for the basket and is not ownership of any
          stock. Stock Tokens are separate rewards providing economic exposure
          only. Availability restricted by jurisdiction.
        </p>
      </section>

      {/* -------------------------------------------------------- key numbers */}
      <section className="numbers">
        <div className="num">
          <div className="num-v">{supply}</div>
          <div className="num-l">Fixed supply — no mint, no tax</div>
        </div>
        <div className="num">
          <div className="num-v">{feePct}%</div>
          <div className="num-l">Protocol fee, 100% buys the basket</div>
        </div>
        <div className="num">
          <div className="num-v">{BASKET_TICKERS.length}</div>
          <div className="num-l">Founding constituents, equal weight</div>
        </div>
        <div className="num">
          <div className="num-v">{threshold}</div>
          <div className="num-l">PENNY held = reward eligibility</div>
        </div>
      </section>

      {/* --------------------------------------------------------- how it works */}
      <section id="how" className="block">
        <h2>How it works</h2>
        <div className="cards3">
          <div className="hcard">
            <div className="hcard-n">1</div>
            <h3>Trade</h3>
            <p>
              Swap ETH ↔ PENNY in a dedicated Uniswap v4 pool on Robinhood
              Chain. A custom hook collects a transparent {feePct}% fee in WETH
              on every swap — both directions, immutable, capped in code.
            </p>
          </div>
          <div className="hcard">
            <div className="hcard-n">2</div>
            <h3>Accumulate</h3>
            <p>
              Collected fees periodically buy five Robinhood Stock Tokens at
              equal value, guarded by Chainlink price checks and fail-closed
              market-session rules. All purchases are onchain and auditable.
            </p>
          </div>
          <div className="hcard">
            <div className="hcard-n">3</div>
            <h3>Receive</h3>
            <p>
              Hold {threshold}+ PENNY at the snapshot, pass the one-time
              eligibility check, opt in with a single signature — and Stock
              Token rewards arrive in your wallet automatically each epoch.
            </p>
          </div>
        </div>
      </section>

      {/* -------------------------------------------------------------- basket */}
      <section id="basket" className="block">
        <h2>The founding basket</h2>
        <p className="block-sub">
          Five small-cap themes, 20% target weight each. The basket rotates:
          constituents can be added or removed through a public 7-day timelock
          with onchain reasons — but rewards already earned never change.
        </p>
        <div className="basket-grid">
          {BASKET.map((b) => (
            <div className="bcard" key={b.ticker}>
              <div className="bcard-top">
                <span className="bcard-ticker">{b.ticker}</span>
                <span className="bcard-weight">20%</span>
              </div>
              <div className="bcard-name">{b.name}</div>
              <div className="bcard-theme">{b.theme}</div>
            </div>
          ))}
        </div>
        <p className="fine">
          Selection snapshot dated 30 Aug 2026; themes shown are the admission
          thesis, not price predictions. Robinhood Stock Tokens are tokenised
          instruments issued by Robinhood Assets (Jersey) Ltd — they provide
          economic exposure and are not shares.
        </p>
      </section>

      {/* -------------------------------------------------------- transparency */}
      <section id="transparency" className="block">
        <h2>Built to be checked, not trusted</h2>
        <div className="cards2">
          <div className="tcard">
            <h3>No admin games</h3>
            <p>
              Fixed 1B supply minted once. No mint function, no transfer tax,
              no blacklist, no pause on transfers. The fee is immutable at{" "}
              {feePct}% and every custody route is wired once and can never be
              redirected — even by the owners.
            </p>
          </div>
          <div className="tcard">
            <h3>Rewards can&apos;t be taken back</h3>
            <p>
              Purchased Stock Tokens sit in a vault no admin can sweep. Reward
              roots activate only after a public challenge window, cumulative
              entitlements can never decrease, and completed claims can never
              be clawed back.
            </p>
          </div>
          <div className="tcard">
            <h3>Everything onchain</h3>
            <p>
              Every fee, purchase, deposit, root, and delivery emits a public
              event. Reward manifests are bit-for-bit reproducible from public
              data. The entire codebase — contracts, indexer, keeper — is open
              source.
            </p>
          </div>
          <div className="tcard">
            <h3>Honest about status</h3>
            <p>
              Not yet audited. Not yet approved by counsel. Trading is not
              live. Mainnet deployment is blocked in code until independent
              audit, legal signoff, and live liquidity verification complete —
              those gates are published in the repo.
            </p>
          </div>
        </div>
        <div className="cta-row center">
          <a
            className="btn btn-primary"
            href={GITHUB_URL}
            target="_blank"
            rel="noreferrer"
          >
            Verify it yourself — GitHub ↗
          </a>
          <Link className="btn btn-secondary" href="/status">
            Protocol status
          </Link>
        </div>
      </section>

      {/* ---------------------------------------------------------------- faq */}
      <section className="block">
        <h2>Straight answers</h2>
        <div className="faq">
          <details>
            <summary>Do I own the stocks?</summary>
            <p>
              No. PENNY is not redeemable for the basket and does not represent
              ownership of Stock Tokens or underlying shares. Stock Tokens you
              receive as rewards are separate assets providing economic
              exposure, and they are yours once delivered.
            </p>
          </details>
          <details>
            <summary>Is this guaranteed income?</summary>
            <p>
              No. Rewards depend entirely on trading volume, and purchases
              pause during market closure, oracle issues, low fee accumulation,
              or emergencies. Nothing here is a promise of returns.
            </p>
          </details>
          <details>
            <summary>Why the eligibility check?</summary>
            <p>
              Stock Tokens are restricted securities — they cannot be delivered
              to U.S. persons and several other jurisdictions. The one-time
              eligibility attestation is what makes automatic delivery legally
              possible at all.
            </p>
          </details>
          <details>
            <summary>When does trading go live?</summary>
            <p>
              After the launch gates close: independent smart-contract audit,
              legal counsel signoff, and verified live liquidity for all five
              Stock Tokens. Progress is public in the repo&apos;s STATUS.md.
            </p>
          </details>
        </div>
      </section>

      {/* ------------------------------------------------------------- footer */}
      <footer className="lfooter">
        <p>
          © {new Date().getFullYear()} Penny Protocol ·{" "}
          <a href={GITHUB_URL} target="_blank" rel="noreferrer">
            GitHub
          </a>{" "}
          · <Link href="/status">Status</Link>
        </p>
        <p className="fine">
          Nothing on this page is investment, legal, or tax advice. This
          project is unaudited and pre-launch; contracts are not deployed to
          mainnet. Cryptoassets are volatile and you can lose everything you
          put in. Stock Token rewards are unavailable in restricted
          jurisdictions including the United States.
        </p>
      </footer>
    </main>
  );
}
