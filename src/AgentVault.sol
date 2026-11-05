// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title AgentVault
/// @notice ETH custody vault with per-tx spend limits; freezes via Reactive callback.
/// @dev Deployed on the origin chain (Ethereum Sepolia by default). Inherits AbstractCallback so only the authorized
///      Lasna reactive contract (via the origin-chain callback proxy) can freeze it.
contract AgentVault is AbstractCallback {
    event SpendAttempted(
        address indexed agent,
        address indexed to,
        uint256 amount,
        bytes32 intentHash
    );
    event Spent(address indexed agent, address indexed to, uint256 amount, bytes32 intentHash);
    event Frozen(address indexed reactiveSender, bytes32 reason);
    event Unfrozen(address indexed by);
    event AgentUpdated(address indexed agent);
    event MaxPerTxUpdated(uint256 maxPerTx);
    event Deposited(address indexed from, uint256 amount);
    event Withdrawn(address indexed to, uint256 amount);

    address public owner;
    address public agent;
    uint256 public maxPerTx;
    bool public paused;

    error NotOwner();
    error NotAgent();
    error Paused();
    error OverLimit();
    error EthTransferFailed();
    error ZeroAddress();

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    /// @param callbackProxy_ Origin-chain Reactive callback proxy.
    /// @param callbackSender_ Address of the AgentGuardReactive contract on Lasna.
    /// @param agent_ Authorized agent EOA / contract allowed to spend.
    /// @param maxPerTx_ Maximum wei per spend call.
    constructor(
        address callbackProxy_,
        address callbackSender_,
        address agent_,
        uint256 maxPerTx_
    ) payable AbstractCallback(IPayable(payable(callbackProxy_)), callbackSender_) {
        if (agent_ == address(0)) revert ZeroAddress();
        owner = msg.sender;
        agent = agent_;
        maxPerTx = maxPerTx_;
    }

    receive() external payable override {
        emit Deposited(msg.sender, msg.value);
    }

    function setAgent(address agent_) external onlyOwner {
        if (agent_ == address(0)) revert ZeroAddress();
        agent = agent_;
        emit AgentUpdated(agent_);
    }

    function setMaxPerTx(uint256 maxPerTx_) external onlyOwner {
        maxPerTx = maxPerTx_;
        emit MaxPerTxUpdated(maxPerTx_);
    }

    function coverDebt() external {
        _coverDebt();
    }

    function unfreeze() external onlyOwner {
        paused = false;
        emit Unfrozen(msg.sender);
    }

    function ownerWithdraw(address payable to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit Withdrawn(to, amount);
    }

    /// @notice Authorized agent spends vault ETH subject to pause + per-tx cap.
    function spend(address payable to, uint256 amount, bytes32 intentHash) external {
        if (msg.sender != agent) revert NotAgent();
        if (paused) revert Paused();
        if (amount > maxPerTx) revert OverLimit();
        if (to == address(0)) revert ZeroAddress();

        emit SpendAttempted(msg.sender, to, amount, intentHash);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
        emit Spent(msg.sender, to, amount, intentHash);
    }

    /// @notice Reactive Network callback entrypoint — freezes the vault.
    /// @dev First arg is injected by the callback proxy (reactive sender address).
    function freeze(address reactiveSender, bytes32 reason)
        external
        onlyServiceProvider
        onlyCallbackSender(reactiveSender)
    {
        paused = true;
        emit Frozen(reactiveSender, reason);
    }
}
