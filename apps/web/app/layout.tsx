import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Penny Stocks",
  description:
    "Claim status UI for PENNY Stock Token rewards. Sample data only — no wallets or signing keys are shipped by this interface.",
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
