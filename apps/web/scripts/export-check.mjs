import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const webRoot = path.resolve(__dirname, "..");
const outDir = path.join(webRoot, "out");
const indexFile = path.join(outDir, "index.html");

if (!fs.existsSync(outDir)) {
  console.error(`export-check FAIL: ${outDir} not found`);
  process.exit(1);
}

if (!fs.existsSync(indexFile)) {
  console.error(`export-check FAIL: ${indexFile} not found`);
  process.exit(1);
}

const html = fs.readFileSync(indexFile, "utf8");
if (!html.includes("Penny Stocks")) {
  console.error(
    'export-check FAIL: out/index.html does not contain "Penny Stocks"',
  );
  process.exit(1);
}

console.log(
  "export-check OK: out/index.html exists and contains 'Penny Stocks'",
);
