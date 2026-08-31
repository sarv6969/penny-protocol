#!/usr/bin/env bash
set -euo pipefail

if command -v forge >/dev/null 2>&1; then
  FORGE_BIN="forge"
elif [ -x "$HOME/.foundry/bin/forge" ]; then
  FORGE_BIN="$HOME/.foundry/bin/forge"
else
  echo "forge not found — run 'curl -L https://foundry.paradigm.xyz | bash' then 'foundryup'" >&2
  exit 1
fi

exec "$FORGE_BIN" "$@"