#!/usr/bin/env bash
set -euo pipefail
export PATH="/home/box/.foundry/bin:$PATH"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BURNER_JSON="${BURNER_JSON:-/workspace/.secrets/reactive_omni_burner.json}"
ADDR=$(python3 -c "import json;print(json.load(open('$BURNER_JSON'))['address'])")
PK=$(python3 -c "import json;print(json.load(open('$BURNER_JSON'))['private_key'])")
BASE_RPC="${BASE_RPC:-https://sepolia.base.org}"
LASNA_RPC="${LASNA_RPC:-https://lasna-rpc.rnk.dev/}"
CALLBACK_PROXY="0x476F44b11F5C942c58f4c8E3d0300E5710743585"
LREACT_FAUCET="0x2afaFD298b23b62760711756088F75B7409f5967"
RISK_TOPIC0="0x4d9695652967743f081c770dddf31932389fdfd01750fe347096e1edd86e90fe"
THRESHOLD="${THRESHOLD:-70}"
MAX_PER_TX="${MAX_PER_TX:-50000000000000000}" # 0.05 ETH
OUT="$ROOT/deployments/lasna-base-sepolia.json"

echo "Burner: $ADDR"
BASE_BAL=$(cast balance "$ADDR" --rpc-url "$BASE_RPC")
echo "Base Sepolia balance (wei): $BASE_BAL"
if [[ "$BASE_BAL" == "0" ]]; then
  echo "ERROR: no Base Sepolia ETH. Abort deploy."
  exit 2
fi

# 1) Deploy oracle on Base
echo "==> Deploy AIRiskOracle"
ORACLE_OUT=$(forge create src/AIRiskOracle.sol:AIRiskOracle \
  --rpc-url "$BASE_RPC" --private-key "$PK" --broadcast \
  --constructor-args "$THRESHOLD" 2>&1)
echo "$ORACLE_OUT"
ORACLE=$(echo "$ORACLE_OUT" | awk '/Deployed to:/ {print $3}')
ORACLE_TX=$(echo "$ORACLE_OUT" | awk '/Transaction hash:/ {print $3}')
echo "ORACLE=$ORACLE"

# 2) Request lREACT if Lasna balance low
LASNA_BAL=$(cast balance "$ADDR" --rpc-url "$LASNA_RPC" || echo 0)
echo "Lasna balance (wei): $LASNA_BAL"
if [[ "$LASNA_BAL" == "0" ]]; then
  echo "==> Requesting lREACT via faucet (0.05 ETH)"
  cast send "$LREACT_FAUCET" "request(address)" "$ADDR" \
    --rpc-url "$BASE_RPC" --private-key "$PK" --value 0.05ether
  sleep 8
  LASNA_BAL=$(cast balance "$ADDR" --rpc-url "$LASNA_RPC")
  echo "Lasna balance after faucet: $LASNA_BAL"
fi

# 3) Deploy reactive on Lasna with funding
echo "==> Deploy AgentGuardReactive"
REACT_VALUE="${REACT_VALUE:-0.02ether}"
REACTIVE_OUT=$(forge create src/AgentGuardReactive.sol:AgentGuardReactive \
  --rpc-url "$LASNA_RPC" --private-key "$PK" --broadcast \
  --value "$REACT_VALUE" \
  --constructor-args "$ORACLE" "$RISK_TOPIC0" "$THRESHOLD" 2>&1)
echo "$REACTIVE_OUT"
REACTIVE=$(echo "$REACTIVE_OUT" | awk '/Deployed to:/ {print $3}')
REACTIVE_TX=$(echo "$REACTIVE_OUT" | awk '/Transaction hash:/ {print $3}')
echo "REACTIVE=$REACTIVE"

# 4) Deploy vault on Base with funding for callback gas
echo "==> Deploy AgentVault"
VAULT_VALUE="${VAULT_VALUE:-0.02ether}"
VAULT_OUT=$(forge create src/AgentVault.sol:AgentVault \
  --rpc-url "$BASE_RPC" --private-key "$PK" --broadcast \
  --value "$VAULT_VALUE" \
  --constructor-args "$CALLBACK_PROXY" "$REACTIVE" "$ADDR" "$MAX_PER_TX" 2>&1)
echo "$VAULT_OUT"
VAULT=$(echo "$VAULT_OUT" | awk '/Deployed to:/ {print $3}')
VAULT_TX=$(echo "$VAULT_OUT" | awk '/Transaction hash:/ {print $3}')
echo "VAULT=$VAULT"

# 5) setVault on reactive
echo "==> setVault on reactive"
SET_TX=$(cast send "$REACTIVE" "setVault(address)" "$VAULT" \
  --rpc-url "$LASNA_RPC" --private-key "$PK" --json | python3 -c "import sys,json; print(json.load(sys.stdin).get('transactionHash',''))")
echo "SET_VAULT_TX=$SET_TX"

python3 - <<PY
import json, time
doc = {
  "network": {"origin": "base-sepolia", "originChainId": 84532, "reactive": "lasna", "reactiveChainId": 5318007},
  "callbackProxy": "$CALLBACK_PROXY",
  "riskFlaggedTopic0": "$RISK_TOPIC0",
  "threshold": int("$THRESHOLD"),
  "deployer": "$ADDR",
  "contracts": {
    "AIRiskOracle": {"address": "$ORACLE", "tx": "$ORACLE_TX"},
    "AgentGuardReactive": {"address": "$REACTIVE", "tx": "$REACTIVE_TX"},
    "AgentVault": {"address": "$VAULT", "tx": "$VAULT_TX"},
  },
  "setVaultTx": "$SET_TX",
  "deployedAt": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
}
open("$OUT","w").write(json.dumps(doc, indent=2)+"\n")
print("Wrote $OUT")
print(json.dumps(doc, indent=2))
PY
