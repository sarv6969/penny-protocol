import Link from "next/link";
import {
  PENNY_DECIMALS,
  PENNY_TOTAL_SUPPLY,
  PROTOCOL_FEE_BPS,
  ELIGIBLE_BALANCE_THRESHOLD,
  BASKET_TICKERS,
} from "@penny/sdk";

const GITHUB_URL = "https://github.com/sarv6969/penny-protocol";

// Snapshot data dated 31 Aug 2026 market close (stockanalysis.com / S&P Global).
// Screening notes only — the protocol's oracles are Chainlink feeds, never this table.
const SNAPSHOT_DATE = "31 Aug 2026";

const BASKET = [
  {
    ticker: "AUR",
    name: "Aurora Innovation",
    theme: "Autonomous trucking",
    exchange: "NASDAQ",
    price: "$5.63",
    mcap: "$11.3B",
    sector: "Physical AI / freight",
    narrative:
      "The leader in self-driving freight. Aurora Driver — a full hardware + software stack — is already hauling driverless loads on ten commercial routes across Texas, with second-generation trucks launched and a plan to scale past 200 driverless trucks. The thesis: trucking is a $900B U.S. market with a permanent driver shortage, and the first company to remove the driver at scale rewrites its economics.",
    stockUrl: "https://robinhood.com/us/en/stocks/AUR/",
    token: "0x373C06c4f7BDe527D7Dae4BA169E42b55E393CeD",
  },
  {
    ticker: "JOBY",
    name: "Joby Aviation",
    theme: "Electric air taxis",
    exchange: "NYSE",
    price: "$6.83",
    mcap: "$6.8B",
    sector: "eVTOL / air mobility",
    narrative:
      "The furthest-along electric air taxi company: FAA certification in progress, Toyota as manufacturing partner, vertiport network deals in Florida, New York and Texas, and a $500M defence acquisition opening a second revenue engine. The thesis: if quiet electric aircraft replace helicopters for short urban hops, the first certified operator owns a new mode of transport.",
    stockUrl: "https://robinhood.com/us/en/stocks/JOBY/",
    token: "0xb334C5cE741B80B5B671F47F5C269Cb193fe8E24",
  },
  {
    ticker: "SOUN",
    name: "SoundHound AI",
    theme: "Voice AI software",
    exchange: "NASDAQ",
    price: "$7.18",
    mcap: "$3.2B",
    sector: "Conversational AI",
    narrative:
      "Independent voice AI powering cars, drive-thrus, restaurants and call centres — revenue up 45% year-over-year to a record quarter, with the LivePerson acquisition adding enterprise customer-service scale. The thesis: every machine gets a voice interface, and businesses that won't hand their customer data to Big Tech need an independent provider.",
    stockUrl: "https://robinhood.com/us/en/stocks/SOUN/",
    token: "0x6E3Dfd9f7e1649BaA14D25cac18C94d62dB10A54",
  },
  {
    ticker: "SMR",
    name: "NuScale Power",
    theme: "Small modular reactors",
    exchange: "NYSE",
    price: "$9.27",
    mcap: "$4.0B",
    sector: "Advanced nuclear",
    narrative:
      "The only small modular reactor design approved by the U.S. nuclear regulator, with $1.9B of liquidity and supplier agreements ready for first deployments. The thesis: AI data centres are creating a once-in-a-generation surge in clean baseload power demand, and factory-built reactors are the way nuclear finally scales.",
    stockUrl: "https://robinhood.com/us/en/stocks/SMR/",
    token: "0x1Eebee7F74517e0279dFb09d25B0407bEEc3FDd6",
  },
  {
    ticker: "CLOV",
    name: "Clover Health",
    theme: "AI-driven health insurance",
    exchange: "NASDAQ",
    price: "$4.15",
    mcap: "$2.2B",
    sector: "Health tech",
    narrative:
      "A Medicare Advantage insurer built around Clover Assistant — AI software that helps physicians catch chronic disease earlier. Membership grew 48% year-over-year with GAAP profitability arriving and full-year guidance raised. The thesis: the only true value-based-care software play trading at small-cap prices, in America's fastest-growing insurance market.",
    stockUrl: "https://robinhood.com/us/en/stocks/CLOV/",
    token: "0x62200915e7DEab1eC7f79fb246daDbB80eACdDd0",
  },
] as const;

// Clearly-labelled SAMPLE values for the hero receipt (no live protocol yet).
const RECEIPT_ROWS = [
  { t: "AUR", n: "AURORA INNOVATION" },
  { t: "JOBY", n: "JOBY AVIATION" },
  { t: "SOUN", n: "SOUNDHOUND AI" },
  { t: "SMR", n: "NUSCALE POWER" },
  { t: "CLOV", n: "CLOVER HEALTH" },
];

const TAPE =
  "AUR ▲ · JOBY ▲ · SOUN ▲ · SMR ▲ · CLOV ▲ · 3% FEE → BASKET · REWARDS EVERY EPOCH · ";

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
              Hold $PENNY.
              <br />
              <em>Earn penny stocks.</em>
            </h1>
            <p>
              Every trade feeds the basket — a {feePct}% fee on $PENNY volume
              buys Stock Tokens tracking five small-cap moonshots. Hold{" "}
              {threshold}+ and pass the one-time check: your share lands in
              your wallet every epoch, automatically.
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

      {/* ------------------------------------------------------------ narrative */}
      <section className="ix-story">
        <div className="ix-story-in">
          <div className="ix-story-side">
            <div className="ix-kicker">THE IDEA</div>
            <h2>
              Why penny stocks,
              <br />
              <em>of all things?</em>
            </h2>
          </div>
          <div className="ix-story-body">
            <p>
              <strong>
                Penny stocks are where retail goes hunting for 10x.
              </strong>{" "}
              Low-priced names with big theses — self-driving trucks, air
              taxis, voice AI, modular nuclear. High risk, high volatility, and
              usually locked behind a brokerage account, one order at a time.
            </p>
            <p>
              <strong>Robinhood put them onchain.</strong> Robinhood Chain
              issues Stock Tokens — tokenised instruments that track real
              equities and trade 24/5 with onchain settlement. For the first
              time, a smart contract can hold exposure to a basket of small-cap
              stocks.
            </p>
            <p>
              <strong>$PENNY turns that into a flywheel.</strong> Instead of
              you picking one penny stock and praying, the token&apos;s own
              trading volume drip-buys a diversified basket of five — and
              distributes it to holders. More trading, more buying. The basket
              rotates as theses play out and new small caps get tokenised.
            </p>
            <p className="ix-story-fine">
              To be precise: Stock Tokens provide economic exposure to the
              underlying equities — they are not brokerage shares, carry no
              voting rights or dividends, and $PENNY itself is never redeemable
              for the basket. Rewards are separate assets that become yours
              only when distributed.
            </p>
          </div>
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
        <div className="ix-stock-grid ix-stock-grid-wide">
          {BASKET.map((b) => (
            <div className="ix-stock" key={b.ticker}>
              <div className="ix-stock-top">
                <span className="ix-stock-logo">{b.ticker.slice(0, 2)}</span>
                <div>
                  <div className="ix-stock-ticker">
                    {b.ticker}{" "}
                    <span className="ix-stock-exch">{b.exchange}</span>
                  </div>
                  <div className="ix-stock-name">{b.name}</div>
                </div>
                <span className="ix-stock-w">20%</span>
              </div>
              <div className="ix-stock-stats">
                <div>
                  <div className="ix-lab">PRICE*</div>
                  <div className="ix-stock-stat">{b.price}</div>
                </div>
                <div>
                  <div className="ix-lab">MARKET CAP*</div>
                  <div className="ix-stock-stat">{b.mcap}</div>
                </div>
                <div>
                  <div className="ix-lab">SECTOR</div>
                  <div className="ix-stock-stat ix-stock-sector">
                    {b.sector}
                  </div>
                </div>
              </div>
              <p className="ix-stock-story">{b.narrative}</p>
              <div className="ix-stock-links">
                <a href={b.stockUrl} target="_blank" rel="noreferrer">
                  STOCK PAGE ↗
                </a>
                <a
                  href={`https://robinhoodchain.blockscout.com/token/${b.token}`}
                  target="_blank"
                  rel="noreferrer"
                >
                  TOKEN CONTRACT ↗
                </a>
              </div>
            </div>
          ))}
          <div className="ix-stock ix-stock-more">
            <div className="ix-lab">BASKET ROTATION</div>
            <div className="ix-stock-more-t">Constituents rotate</div>
            <p>
              Stocks join or leave through a public 7-day timelock with onchain
              reasons — rewards already earned never change. As theses play out
              and new small caps get tokenised, the shelf refreshes.
            </p>
            <a href={GITHUB_URL} target="_blank" rel="noreferrer">
              VIEW POLICY →
            </a>
          </div>
        </div>
        <p className="fine">
          *Prices and market caps are a dated screening snapshot ({SNAPSHOT_DATE}{" "}
          market close, S&amp;P Global via stockanalysis.com) — shown for
          context, never used by the protocol, which prices purchases through
          official Chainlink feeds at execution. Narratives are the admission
          thesis, not price predictions; every company here is unprofitable
          and highly volatile. Robinhood Stock Tokens are tokenised
          instruments issued by Robinhood Assets (Jersey) Ltd — they provide
          economic exposure and are not shares.
        </p>
      </section>

      {/* ---------------------------------------------------------------- how */}
      <section id="how" className="ix-how">
        <h2>How it works</h2>
        <p className="ix-how-sub">
          Three moving parts. Each one is a contract you can read, and every
          hop between them is a public onchain event.
        </p>
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

        {/* full lifecycle walk-through */}
        <div className="ix-life">
          <div className="ix-kicker">ONE EPOCH, START TO FINISH</div>
          <div className="ix-life-rows">
            <div className="ix-life-row">
              <span className="ix-life-n">1</span>
              <div>
                <strong>Someone trades.</strong> A swap in the ETH/$PENNY pool
                fires the fee hook: {feePct}% of the WETH leg goes straight to
                the FeeCollector. Nothing is skimmed — the fee address is wired
                once and can never be changed.
              </div>
            </div>
            <div className="ix-life-row">
              <span className="ix-life-n">2</span>
              <div>
                <strong>The keeper checks every 15 minutes.</strong> When
                enough WETH has pooled and markets are open, it triggers the
                basket purchase — five stocks, equal value, priced by
                Chainlink. If even one leg can&apos;t execute safely, the whole
                purchase waits. No partial baskets, ever.
              </div>
            </div>
            <div className="ix-life-row">
              <span className="ix-life-n">3</span>
              <div>
                <strong>Purchased tokens land in the vault.</strong> A
                RewardVault no admin can sweep. From this moment the stocks are
                spoken for — they can only ever leave toward entitled holders.
              </div>
            </div>
            <div className="ix-life-row">
              <span className="ix-life-n">4</span>
              <div>
                <strong>A snapshot decides who&apos;s in.</strong> The indexer
                reads every wallet&apos;s balance at a finalized block. Hold{" "}
                {threshold}+ $PENNY there and you&apos;re in the epoch,
                pro-rata to your balance. Sell after the snapshot? That
                epoch&apos;s entitlement is still yours.
              </div>
            </div>
            <div className="ix-life-row">
              <span className="ix-life-n">5</span>
              <div>
                <strong>The epoch publishes with a challenge window.</strong>{" "}
                Entitlements go onchain as a Merkle root anyone can recompute
                from public data. It activates only after a public delay — and
                once you&apos;re owed something, no future epoch can reduce it.
              </div>
            </div>
            <div className="ix-life-row">
              <span className="ix-life-n">6</span>
              <div>
                <strong>Stocks arrive in your wallet.</strong> Opted-in wallets
                get delivered automatically — the relayer pays gas, and the
                math guarantees rewards can only land in the wallet that earned
                them. Everyone else can self-claim all missed epochs in one
                transaction, whenever.
              </div>
            </div>
          </div>
          <p className="ix-life-fine">
            Purchases and epochs pause for market closure, stale prices, thin
            liquidity, or emergencies — the system fails closed and resumes
            where it left off. &quot;Every epoch&quot; means every epoch the
            rails are safe, not a promised schedule.
          </p>
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
