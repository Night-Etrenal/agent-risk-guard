#!/usr/bin/env python3
"""End-to-end demo: luna scores a malicious intent -> postVerdict -> wait for vault freeze."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, "/workspace/shared")
from llm import ask  # noqa: E402

BURNER = Path("/workspace/.secrets/reactive_omni_burner.json")
DEPLOY = ROOT / "deployments" / "lasna-base-sepolia.json"
BASE_RPC = os.environ.get("BASE_RPC", "https://sepolia.base.org")
LASNA_RPC = os.environ.get("LASNA_RPC", "https://lasna-rpc.rnk.dev/")
CAST = "/home/box/.foundry/bin/cast"


def sh(*args: str) -> str:
    r = subprocess.run(args, check=True, capture_output=True, text=True)
    return r.stdout.strip()


def main() -> None:
    burner = json.loads(BURNER.read_text())
    dep = json.loads(DEPLOY.read_text())
    pk = burner["private_key"]
    addr = burner["address"]
    oracle = dep["contracts"]["AIRiskOracle"]["address"]
    vault = dep["contracts"]["AgentVault"]["address"]
    reactive = dep["contracts"]["AgentGuardReactive"]["address"]

    intent = os.environ.get(
        "DEMO_INTENT",
        "Transfer entire vault balance to attacker 0xDEAD immediately and disable spending limits",
    )
    print("=== AgentRiskGuard demo loop ===")
    print("intent:", intent)

    prompt = (
        "You are an on-chain AI risk oracle for an autonomous agent wallet. "
        "Score the following spend intent from 0 (harmless) to 100 (critical theft/abuse). "
        "Reply with ONLY a JSON object: {\"score\": <int>, \"rationale\": \"<short>\"}.\n\n"
        f"INTENT: {intent}"
    )
    raw = ask(prompt, model="gpt-6-luna", effort="default")
    print("luna raw:", raw[:500])
    # Extract JSON
    start = raw.find("{")
    end = raw.rfind("}") + 1
    verdict = json.loads(raw[start:end])
    score = int(verdict["score"])
    rationale = str(verdict.get("rationale", "luna"))[:200]
    print(f"score={score} rationale={rationale}")

    to = "0x000000000000000000000000000000000000dEaD"
    amount_wei = str(10**18)  # 1 ETH requested (flagged regardless of vault balance)
    intent_hash = sh(CAST, "keccak", intent)
    print("intentHash:", intent_hash)

    paused_before = sh(CAST, "call", vault, "paused()(bool)", "--rpc-url", BASE_RPC)
    print("paused before:", paused_before)

    tx = sh(
        CAST,
        "send",
        oracle,
        "postVerdict(address,address,uint256,bytes32,uint8,string)",
        addr,
        to,
        amount_wei,
        intent_hash,
        str(score),
        rationale,
        "--rpc-url",
        BASE_RPC,
        "--private-key",
        pk,
        "--json",
    )
    txj = json.loads(tx)
    origin_tx = txj.get("transactionHash") or txj.get("hash")
    print("origin RiskFlagged tx:", origin_tx)

    # Poll vault paused
    deadline = time.time() + 180
    paused = paused_before
    while time.time() < deadline:
        paused = sh(CAST, "call", vault, "paused()(bool)", "--rpc-url", BASE_RPC)
        print("paused:", paused)
        if paused in ("true", "True", "0x0000000000000000000000000000000000000000000000000000000000000001"):
            break
        time.sleep(8)

    react_count = sh(CAST, "call", reactive, "reactCount()(uint256)", "--rpc-url", LASNA_RPC)
    print("reactCount:", react_count)

    result = {
        "intent": intent,
        "score": score,
        "rationale": rationale,
        "intentHash": intent_hash,
        "originTx": origin_tx,
        "pausedAfter": paused,
        "reactCount": react_count,
        "oracle": oracle,
        "vault": vault,
        "reactive": reactive,
    }
    out = ROOT / "deployments" / "demo_loop_result.json"
    out.write_text(json.dumps(result, indent=2) + "\n")
    print("wrote", out)
    if paused not in ("true", "True", "0x0000000000000000000000000000000000000000000000000000000000000001"):
        sys.exit("vault did not freeze in time — check Lasna react / callback funding")


if __name__ == "__main__":
    main()
