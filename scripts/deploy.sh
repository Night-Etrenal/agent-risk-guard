#!/usr/bin/env bash
set -euo pipefail
export PATH="/home/box/.foundry/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BURNER_JSON="${BURNER_JSON:-/workspace/.secrets/reactive_omni_burner.json}"
ADDR=$(python3 -c "import json;print(json.load(open('$BURNER_JSON'))['address'])")
PK=$(python3 -c "import json;print(json.load(open('$BURNER_JSON'))['private_key'])")

# Defaults: Ethereum Sepolia (Reactive Meets AI allows any Reactive-supported chain).
# Base Sepolia was preferred but faucet-gated (needs mainnet ETH).
ORIGIN_RPC="${ORIGIN_RPC:-https://ethereum-sepolia-rpc.publicnode.com}"
ORIGIN_RPC_FALLBACK="${ORIGIN_RPC_FALLBACK:-https://1rpc.io/sepolia}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
CALLBACK_PROXY="${CALLBACK_PROXY:-0xAa14d9Cd0f788Ca23d11805986C1d8bd035D23b4}"
LREACT_FAUCET="${LREACT_FAUCET:-0x9b9BB25f1A81078C544C829c5EB7822d747Cf434}"
ORIGIN_CHAIN_ID="${ORIGIN_CHAIN_ID:-11155111}"
ORIGIN_NAME="${ORIGIN_NAME:-ethereum-sepolia}"
RISK_TOPIC0="${RISK_TOPIC0:-0x4d9695652967743f081c770dddf31932389fdfd01750fe347096e1edd86e90fe}"
THRESHOLD="${THRESHOLD:-70}"
MAX_PER_TX="${MAX_PER_TX:-50000000000000000}" # 0.05 ETH
FAUCET_VALUE="${FAUCET_VALUE:-0.015ether}"
REACT_VALUE="${REACT_VALUE:-0.02ether}"
VAULT_VALUE="${VAULT_VALUE:-0.012ether}"
OUT="$ROOT/deployments/lasna-sepolia.json"
LEGACY_OUT="$ROOT/deployments/lasna-base-sepolia.json"

rpc_ok() {
  cast chain-id --rpc-url "$1" >/dev/null 2>&1
}

if ! rpc_ok "$ORIGIN_RPC"; then
  echo "WARN: primary ORIGIN_RPC failed, trying fallback $ORIGIN_RPC_FALLBACK"
  ORIGIN_RPC="$ORIGIN_RPC_FALLBACK"
fi

echo "Burner: $ADDR"
echo "Origin: $ORIGIN_NAME ($ORIGIN_CHAIN_ID) via $ORIGIN_RPC"
ORIGIN_BAL=$(cast balance "$ADDR" --rpc-url "$ORIGIN_RPC")
echo "Origin balance (wei): $ORIGIN_BAL"
if [[ "$ORIGIN_BAL" == "0" ]]; then
  echo "ERROR: no origin-chain ETH. Abort deploy."
  exit 2
fi

# 1) Deploy oracle on origin
echo "==> Deploy AIRiskOracle"
ORACLE_OUT=$(forge create src/AIRiskOracle.sol:AIRiskOracle \
  --rpc-url "$ORIGIN_RPC" --private-key "$PK" --broadcast \
  --constructor-args "$THRESHOLD" 2>&1)
echo "$ORACLE_OUT"
ORACLE=$(echo "$ORACLE_OUT" | awk '/Deployed to:/ {print $3}')
ORACLE_TX=$(echo "$ORACLE_OUT" | awk '/Transaction hash:/ {print $3}')
echo "ORACLE=$ORACLE"
if [[ -z "$ORACLE" ]]; then
  echo "ERROR: oracle deploy failed"
  exit 3
fi

# 2) Request lREACT if Lasna balance low
LASNA_BAL=$(cast balance "$ADDR" --rpc-url "$LASNA_RPC" || echo 0)
echo "Lasna balance (wei): $LASNA_BAL"
FAUCET_TX=""
if [[ "$LASNA_BAL" == "0" ]]; then
  echo "==> Requesting lREACT via faucet ($FAUCET_VALUE → ~1.5 lREACT)"
  FAUCET_RAW=$(cast send "$LREACT_FAUCET" "request(address)" "$ADDR" \
    --rpc-url "$ORIGIN_RPC" --private-key "$PK" --value "$FAUCET_VALUE" --json 2>&1) || {
    echo "ERROR: faucet request failed: $FAUCET_RAW"
    exit 4
  }
  FAUCET_TX=$(echo "$FAUCET_RAW" | python3 -c "import sys,json; print(json.load(sys.stdin).get('transactionHash',''))")
  echo "FAUCET_TX=$FAUCET_TX"
  echo "==> Polling Lasna balance (up to ~3 min)"
  deadline=$((SECONDS + 180))
  while (( SECONDS < deadline )); do
    sleep 8
    LASNA_BAL=$(cast balance "$ADDR" --rpc-url "$LASNA_RPC" || echo 0)
    echo "  Lasna balance: $LASNA_BAL"
    if [[ "$LASNA_BAL" != "0" ]]; then
      break
    fi
  done
  if [[ "$LASNA_BAL" == "0" ]]; then
    echo "ERROR: lREACT never arrived after faucet. Partial state recorded."
    python3 - <<PY
import json, time
doc = {
  "status": "faucet_pending",
  "network": {"origin": "$ORIGIN_NAME", "originChainId": int("$ORIGIN_CHAIN_ID"), "reactive": "lasna", "reactiveChainId": 5318007},
  "callbackProxy": "$CALLBACK_PROXY",
  "lreactFaucet": "$LREACT_FAUCET",
  "riskFlaggedTopic0": "$RISK_TOPIC0",
  "threshold": int("$THRESHOLD"),
  "deployer": "$ADDR",
  "contracts": {"AIRiskOracle": {"address": "$ORACLE", "tx": "$ORACLE_TX"}},
  "faucetTx": "$FAUCET_TX",
  "deployedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
  "note": "lREACT not credited within 180s; reactive+vault deploy deferred.",
}
open("$OUT","w").write(json.dumps(doc, indent=2)+"\n")
open("$LEGACY_OUT","w").write(json.dumps({"status":"superseded","see":"lasna-sepolia.json","note":"Origin pivoted to Ethereum Sepolia"}, indent=2)+"\n")
print(json.dumps(doc, indent=2))
PY
    exit 5
  fi
fi

# 3) Deploy reactive on Lasna with funding (lREACT)
echo "==> Deploy AgentGuardReactive (value=$REACT_VALUE)"
REACTIVE_OUT=$(forge create src/AgentGuardReactive.sol:AgentGuardReactive \
  --rpc-url "$LASNA_RPC" --private-key "$PK" --broadcast \
  --value "$REACT_VALUE" \
  --constructor-args "$ORACLE" "$RISK_TOPIC0" "$THRESHOLD" "$ORIGIN_CHAIN_ID" 2>&1)
echo "$REACTIVE_OUT"
REACTIVE=$(echo "$REACTIVE_OUT" | awk '/Deployed to:/ {print $3}')
REACTIVE_TX=$(echo "$REACTIVE_OUT" | awk '/Transaction hash:/ {print $3}')
echo "REACTIVE=$REACTIVE"
if [[ -z "$REACTIVE" ]]; then
  echo "ERROR: reactive deploy failed"
  exit 6
fi

# 4) Deploy vault on origin with funding for callback gas
echo "==> Deploy AgentVault (value=$VAULT_VALUE)"
VAULT_OUT=$(forge create src/AgentVault.sol:AgentVault \
  --rpc-url "$ORIGIN_RPC" --private-key "$PK" --broadcast \
  --value "$VAULT_VALUE" \
  --constructor-args "$CALLBACK_PROXY" "$REACTIVE" "$ADDR" "$MAX_PER_TX" 2>&1)
echo "$VAULT_OUT"
VAULT=$(echo "$VAULT_OUT" | awk '/Deployed to:/ {print $3}')
VAULT_TX=$(echo "$VAULT_OUT" | awk '/Transaction hash:/ {print $3}')
echo "VAULT=$VAULT"
if [[ -z "$VAULT" ]]; then
  echo "ERROR: vault deploy failed"
  exit 7
fi

# 5) setVault on reactive
echo "==> setVault on reactive"
SET_TX=$(cast send "$REACTIVE" "setVault(address)" "$VAULT" \
  --rpc-url "$LASNA_RPC" --private-key "$PK" --json | python3 -c "import sys,json; print(json.load(sys.stdin).get('transactionHash',''))")
echo "SET_VAULT_TX=$SET_TX"

ORIGIN_BAL_AFTER=$(cast balance "$ADDR" --rpc-url "$ORIGIN_RPC")
LASNA_BAL_AFTER=$(cast balance "$ADDR" --rpc-url "$LASNA_RPC")

python3 - <<PY
import json, time
doc = {
  "status": "deployed",
  "network": {
    "origin": "$ORIGIN_NAME",
    "originChainId": int("$ORIGIN_CHAIN_ID"),
    "originRpc": "$ORIGIN_RPC",
    "reactive": "lasna",
    "reactiveChainId": 5318007,
    "reactiveRpc": "$LASNA_RPC",
  },
  "callbackProxy": "$CALLBACK_PROXY",
  "lreactFaucet": "$LREACT_FAUCET",
  "riskFlaggedTopic0": "$RISK_TOPIC0",
  "threshold": int("$THRESHOLD"),
  "deployer": "$ADDR",
  "contracts": {
    "AIRiskOracle": {"address": "$ORACLE", "tx": "$ORACLE_TX"},
    "AgentGuardReactive": {"address": "$REACTIVE", "tx": "$REACTIVE_TX"},
    "AgentVault": {"address": "$VAULT", "tx": "$VAULT_TX"},
  },
  "faucetTx": "$FAUCET_TX",
  "setVaultTx": "$SET_TX",
  "balancesAfter": {"originWei": "$ORIGIN_BAL_AFTER", "lasnaWei": "$LASNA_BAL_AFTER"},
  "deployedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
open("$OUT","w").write(json.dumps(doc, indent=2)+"\n")
open("$LEGACY_OUT","w").write(json.dumps({
  "status": "superseded",
  "see": "lasna-sepolia.json",
  "note": "Origin pivoted to Ethereum Sepolia (Reactive Meets AI allows any Reactive-supported chain; Base Sepolia faucet was blocked).",
}, indent=2)+"\n")
print("Wrote $OUT")
print(json.dumps(doc, indent=2))
PY
