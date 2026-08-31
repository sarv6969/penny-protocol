import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Penny Protocol — one token, a rotating basket of small-cap moonshots",
  description:
    "$PENNY trades on Robinhood Chain. 3% of every trade buys Robinhood Stock Tokens across five small-cap themes; eligible holders receive rewards automatically. Pre-launch, open source, unaudited.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
