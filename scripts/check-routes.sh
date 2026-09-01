#!/usr/bin/env bash
# Live executable-route check: LiFi quote vs Chainlink oracle for canary candidates.
# Exit 0 if at least one candidate is inside the deviation cap.
set -uo pipefail
export PATH="${HOME}/.foundry/bin:${PATH}"
RPC="${RPC_URL:-https://rpc.mainnet.chain.robinhood.com}"
WETH=0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73
ETH_FEED=0x78F3556b67E17Df817D51Ef5a990cDaF09E8d3A9
CAP_BPS="${MAX_QUOTE_DEVIATION_BPS:-500}"
PROBE_WETH=${PROBE_WETH:-20000000000000000}   # 0.02 WETH
FROM=${QUOTE_FROM:-0xc9997b2bb65d408af9042714ea779585b59faf59}

CANDIDATES=(
  "USAR:0xA994d3684e8400A6c8078226925779FdeE682DD9:0xd917B029C761D264c6A312BBbcDA868658eF86a6"
  "RKLB:0x045477BF65Aef6f4F2386ad0164579e48381CC74:0x3b14C39E89D60D627b42a1A4CA45b5bb45Fc12e2"
  "RGTI:0x2A045cF1C49c61c166C036d2f06FA2D2d984f765:0x284358abc07F9359f19f4b5b4aC91901Be2597Ba"
  "CLSK:0x810c12D3a554Bc47fd39597Fe3b3AAC4941F50eF:0xcBB95BBF36099d34dA091dc6Fa6F49EfA257Cee3"
  "IONQ:0x22EfeC4919baf55F360E0EDee4AbEB26DE4971eb:0x558378E000D634A36593E338eBacdd6207640EfE"
)

ETH_RAW=$(cast call "$ETH_FEED" "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url "$RPC" | sed -n 2p | awk '{print $1}')
echo "Chainlink ETH/USD: $(python3 -c "print(f'\${$ETH_RAW/1e8:,.2f}')")"
echo "deviation cap: ${CAP_BPS} bps | probe: 0.02 WETH"
echo

PASSED=0
for row in "${CANDIDATES[@]}"; do
  T="${row%%:*}"; rest="${row#*:}"; FEED="${rest%%:*}"; TOK="${rest##*:}"
  CL=$(cast call "$FEED" "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url "$RPC" | sed -n 2p | awk '{print $1}')
  Q=$(curl -s "https://li.quest/v1/quote?fromChain=4663&toChain=4663&fromToken=${WETH}&toToken=${TOK}&fromAmount=${PROBE_WETH}&fromAddress=${FROM}&slippage=0.03")
  OUT=$(echo "$Q" | python3 -c "import json,sys; d=json.load(sys.stdin); print('' if 'message' in d else d['estimate']['toAmount'])")
  TOOL=$(echo "$Q" | python3 -c "import json,sys; d=json.load(sys.stdin); print('' if 'message' in d else d.get('tool',''))")
  if [ -z "$OUT" ]; then printf '%-5s NO ROUTE\n' "$T"; continue; fi
  RES=$(python3 -c "
cl=$CL/1e8; out=$OUT/1e18; eth=$ETH_RAW/1e8
usd=($PROBE_WETH/1e18)*eth
eff=usd/out if out else 0
dev=10000*(eff-cl)/cl
print(f'{cl:.2f}|{eff:.2f}|{dev:+.0f}|{1 if abs(dev)<=$CAP_BPS else 0}')")
  IFS='|' read -r CLP EFF DEV OK <<< "$RES"
  if [ "$OK" = "1" ]; then PASSED=$((PASSED+1)); MARK="PASS"; else MARK="FAIL"; fi
  printf '%-5s oracle=$%-8s exec=$%-8s dev=%+5s bps  %-10s %s\n' "$T" "$CLP" "$EFF" "$DEV" "$TOOL" "$MARK"
done
echo
echo "candidates passing: $PASSED"
[ "$PASSED" -ge 1 ]
