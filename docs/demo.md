# AgentRiskGuard — Demo Video

**Reactive Omni Buildathon · Reactive Meets AI**

English narrated slide demo (1920×1080, ~2:22) covering the problem, architecture, deployed contracts, live AI verdict (score 100), the three cross-chain transaction hashes, and `AgentVault.paused() == true`.

## Public video (no login)

**Release asset:** https://github.com/Night-Etrenal/agent-risk-guard/releases/download/demo-v1/AgentRiskGuard-demo.mp4

**Release page:** https://github.com/Night-Etrenal/agent-risk-guard/releases/tag/demo-v1

Local copy in this repo: [`docs/media/AgentRiskGuard-demo.mp4`](./media/AgentRiskGuard-demo.mp4)

## Proven loop (Ethereum Sepolia ↔ Lasna)

| Step | Detail |
|---|---|
| AI score | luna → **100** / 100 (threshold 70) |
| AIRiskOracle | `0x4B7F4C30f8BC1794771cFeF5584a4685DE965FFb` (Sepolia) |
| AgentGuardReactive | `0x4B7F4C30f8BC1794771cFeF5584a4685DE965FFb` (Lasna) |
| AgentVault | `0xF3E0400eD7A25950Af6dEe74896D15AC763024E6` (Sepolia) |
| Origin `RiskFlagged` | `0x2e15843ff9408c1b0574d7d378d257123622433086b3633fb963dbe3f7bbc6b3` |
| Lasna `react` | `0xb2a993a20162668b67e907e6fca605abf474c40a62c9d5d486f4c6b8abbb3a59` |
| Freeze callback | `0x3b70979ee19fbdef2899dc66b7196682ec1e523630eb9633fec6506dd9dc8152` |
| Result | `paused == true`, reactCount `1` |

Full JSON: [`deployments/lasna-sepolia.json`](../deployments/lasna-sepolia.json), [`deployments/demo_loop_result.json`](../deployments/demo_loop_result.json).
