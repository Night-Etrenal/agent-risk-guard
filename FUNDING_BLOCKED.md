# FUNDING_BLOCKED — Base Sepolia ETH

**Status:** Blocked on public faucet access (captcha / login / mainnet-balance gates). Code, forge build, and 8 unit tests are complete. On-chain deploy deferred.

## Addresses awaiting ETH

| Role | Address |
|---|---|
| Executor burner (has private key in `/workspace/.secrets/reactive_omni_burner.json`) | `0x068F25B1B065DD98c5034d50118EEc3d2a3f32F2` |
| Parent-announced burner (browser faucet target; key not in secrets file at write time) | `0xeE374D2EE9a25f4D527b0032822C3b31d08191C3` |

Both balances were `0` on `https://sepolia.base.org` at last check (America/Los_Angeles morning 2026-11-05).

## Faucets attempted (curl / API)

- Google Cloud Web3 faucet — HTTP 405
- Alchemy Base Sepolia page — captcha / mainnet activity gate
- Coinbase CDP `/v2/evm/faucet` — unauthorized (no CDP key)
- LearnWeb3 faucet API — TLS / unreachable
- Bwarelabs — TLS error
- Optimism Superchain faucet API — 404
- QuickNode faucet claim API — HTML landing, no free drip
- Chainlink / Chainstack — wallet connect + mainnet balance requirements

## What unblocks deploy

1. Send **≥ 0.08 ETH** Base Sepolia to `0x068F25B1B065DD98c5034d50118EEc3d2a3f32F2` (or restore parent burner key for `0xeE374D…` if that address is funded instead).
2. Run `./scripts/deploy.sh` then `python3 scripts/demo_loop.py`.
3. Script will request lREACT via `0x2afaFD298b23b62760711756088F75B7409f5967` automatically.

No mainnet funds and no user primary keys were used.
