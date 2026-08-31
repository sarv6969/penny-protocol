"use client";

import { useState } from "react";

export interface SampleManifestClaim {
  wallet: string;
  eligible: boolean;
  cumulative?: Record<string, string>;
  note?: string;
}

export function ClaimLookup({ claims }: { claims: SampleManifestClaim[] }) {
  const [query, setQuery] = useState("");
  const trimmed = query.trim().toLowerCase();
  const rows =
    trimmed.length < 6
      ? null
      : claims.filter((c) => c.wallet.toLowerCase().includes(trimmed));

  return (
    <div className="card">
      <form
        className="lookup"
        onSubmit={(e) => e.preventDefault()}
        role="search"
      >
        <input
          type="text"
          inputMode="text"
          placeholder="Paste a wallet address (0x…) to look up sample eligibility"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          aria-label="Look up sample wallet eligibility"
        />
        <button type="submit">Look up</button>
      </form>

      {rows === null ? (
        <p className="dim">
          Enter at least 6 characters of a 0x address to filter the sample data.
        </p>
      ) : rows.length === 0 ? (
        <p className="dim">No sample entry matches that address.</p>
      ) : (
        <ul className="plain">
          {rows.map((c) => (
            <li key={c.wallet}>
              <code>{c.wallet}</code>{" "}
              {c.eligible ? (
                <span className="tag ok">eligible</span>
              ) : (
                <span className="tag no">not eligible</span>
              )}
              {c.eligible && c.cumulative ? (
                <span className="dim">
                  {" "}
                  — {Object.entries(c.cumulative).length} assets accruing
                </span>
              ) : null}
              {c.note ? <span className="dim"> — {c.note}</span> : null}
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
