// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title AgentGuardReactive
/// @notice Lasna reactive contract: watches AIRiskOracle.RiskFlagged on Base Sepolia
///         and callbacks AgentVault.freeze on the destination chain.
contract AgentGuardReactive is AbstractReactive {
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;
    uint64 public constant CALLBACK_GAS_LIMIT = 1_000_000;
    uint8 public constant DEFAULT_THRESHOLD = 70;

    address public owner;
    address public oracle;
    address public vault;
    uint256 public riskFlaggedTopic0;
    uint8 public threshold;
    uint256 public reactCount;

    event Reacted(address agent, address to, uint256 amount, bytes32 intentHash, uint8 score);
    event VaultUpdated(address vault);
    event ThresholdUpdated(uint8 threshold);

    error NotOwner();
    error VaultNotSet();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param oracle_ AIRiskOracle address on Base Sepolia.
    /// @param riskFlaggedTopic0_ topic0 of RiskFlagged.
    /// @param threshold_ Minimum score that triggers freeze callback.
    constructor(address oracle_, uint256 riskFlaggedTopic0_, uint8 threshold_) payable {
        owner = msg.sender;
        oracle = oracle_;
        riskFlaggedTopic0 = riskFlaggedTopic0_;
        threshold = threshold_ == 0 ? DEFAULT_THRESHOLD : threshold_;

        SYSTEM.subscribe(
            BASE_SEPOLIA_CHAIN_ID,
            oracle_,
            riskFlaggedTopic0_,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    function setVault(address vault_) external onlyOwner {
        vault = vault_;
        emit VaultUpdated(vault_);
    }

    function setThreshold(uint8 threshold_) external onlyOwner {
        threshold = threshold_;
        emit ThresholdUpdated(threshold_);
    }

    function coverDebt() external {
        _coverDebt();
    }

    /// @inheritdoc IReactive
    function react(LogRecord calldata log_) external onlySystem {
        // RiskFlagged(address indexed agent, address indexed to, uint256 amount, bytes32 intentHash, uint8 score)
        // topics: [topic0, agent, to]; data ABI: (uint256 amount, bytes32 intentHash, uint8 score)
        if (log_.chainId != BASE_SEPOLIA_CHAIN_ID) return;
        if (log_.contractAddress != oracle) return;
        if (log_.topic0 != riskFlaggedTopic0) return;

        address agent = address(uint160(log_.topic1));
        address to = address(uint160(log_.topic2));
        (uint256 amount, bytes32 intentHash, uint8 score) =
            abi.decode(log_.data, (uint256, bytes32, uint8));

        if (score < threshold) return;
        if (vault == address(0)) return; // not configured yet; do not revert (Omni still bills reverts)

        bytes memory payload = abi.encodeWithSignature(
            "freeze(address,bytes32)",
            address(0),
            intentHash
        );

        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: BASE_SEPOLIA_CHAIN_ID,
                recipient: vault,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );

        unchecked {
            ++reactCount;
        }
        emit Reacted(agent, to, amount, intentHash, score);
    }
}
