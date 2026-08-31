#!/usr/bin/env bash
# Secret scan (portable: bash + grep only, no rg/gitleaks required).
# Tier 1 (HARD FAIL) — actual key material in committed source:
#   * ASN.1 / PEM private key blocks, anywhere;
#   * "truthy" secret assignments of 16+ chars (API_KEY/SECRET/PRIVATE_TOKEN/SEED...).
# Tier 2 (REVIEW) — potential hex blobs / sensitive words outside docs/fixtures/caches;
#   reported as warnings (zero-hash constants and test fixtures are the known-benign hits).
# Untracked root .env (gitignored) is intentionally not scanned: instead we assert nothing
# env-like is tracked/staged, so a stray .env can never leak through a commit.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

### Guard: no env files may be tracked or staged
STAGED_ENV="$(git status --porcelain --untracked-files=no 2>/dev/null | grep -E '\.env' | grep -v '\.example' || true)"
if [ -n "${STAGED_ENV}" ]; then
  echo "[secret-scan] FAIL — an .env file is tracked/staged; remove it before committing:"
  printf '%s\n' "${STAGED_ENV}"
  exit 1
fi

EXCLUDES=(--exclude-dir=node_modules --exclude-dir=lib --exclude-dir=out --exclude-dir=dist
          --exclude-dir=dist-build --exclude-dir=.git --exclude-dir=.turbo --exclude-dir=cache
          --exclude-dir=fixtures --exclude-dir=docs --exclude-dir=.next --exclude=.env --exclude=coverage-data*)

FILES="$(grep -rIl "" --include '*.sol' --include '*.ts' --include '*.js' --include '*.mjs' \
        --include '*.json' --include '*.toml' --include '*.sh' --include '*.yml' --include '*.yaml' \
        --include '*.md' "${EXCLUDES[@]}" . 2>/dev/null || true)"

echo "[secret-scan] Tier 1: scanning $(echo "${FILES}" | grep -c . || true) committed files for key material..."
T1="$(printf '%s\n' "${FILES}" | xargs grep -lE --  \
  'BEGIN (RSA |EC |DSA |OPENSSH |PGP )?PRIVATE KEY' \
  2>/dev/null | grep -v '\.jks$' || true)"
T1_ASSIGN="$(printf '%s\n' "${FILES}" | xargs grep -lniE -- \
  '(API[_-]?KEY|SECRET|PRIVATE([-_]?TOKEN|_TOKEN)?|PASSWORD|SEED_PHRASE|MNEMONIC)\s*=\s*["'"'"']?[A-Za-z0-9_\-]{16,}' \
  2>/dev/null || true)"

if [ -n "${T1}" ] || [ -n "${T1_ASSIGN}" ]; then
  echo "[secret-scan] FAIL — likely key material found:"
  printf '%s\n' "${T1}" "${T1_ASSIGN}" | sort -u | sed '/^$/d'
  exit 1
fi

echo "[secret-scan] Tier 1: PASS"
echo "[secret-scan] Tier 2: reporting review hits (64-hex blobs / sensitive words); exit code stays 0..."
printf '%s\n' "${FILES}" | xargs grep -nHE -- '0x[a-f0-9]{64}|private key|seed phrase|api[_-]?key' 2>/dev/null \
  | grep -ivE 'zero|0x0{64}' | head -20 || true
echo "[secret-scan] done"
echo "[secret-scan] NOTE: local .env is gitignored+untracked — rotate/delete any real keys stored there."