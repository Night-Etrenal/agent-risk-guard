// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { Vm } from "forge-std/Vm.sol";
import { AIRiskOracle } from "../src/AIRiskOracle.sol";
import { AgentVault } from "../src/AgentVault.sol";

/// @dev Local unit tests (no Lasna). Reactive react() path is covered by integration demo on testnet.
contract AgentRiskGuardTest is Test {
    AIRiskOracle internal oracle;
    AgentVault internal vault;

    address internal constant PROXY = address(0x476F44b11F5C942c58f4c8E3d0300E5710743585);
    address internal reactive;
    address internal owner;
    address internal agent;
    address internal outsider;

    event RiskFlagged(
        address indexed agent,
        address indexed to,
        uint256 amount,
        bytes32 intentHash,
        uint8 score
    );
    event Frozen(address indexed reactiveSender, bytes32 reason);
    event SpendAttempted(
        address indexed agent,
        address indexed to,
        uint256 amount,
        bytes32 intentHash
    );

    function setUp() public {
        owner = address(this);
        agent = makeAddr("agent");
        outsider = makeAddr("outsider");
        reactive = makeAddr("reactive");

        oracle = new AIRiskOracle(70);
        vault = new AgentVault{value: 1 ether}(PROXY, reactive, agent, 0.1 ether);
        vm.deal(address(vault), 1 ether);
    }

    function test_postVerdict_emitsRiskFlagged_whenScoreHigh() public {
        bytes32 intent = keccak256("drain treasury to attacker");
        vm.expectEmit(true, true, false, true);
        emit RiskFlagged(agent, outsider, 1 ether, intent, 95);
        oracle.postVerdict(agent, outsider, 1 ether, intent, 95, "high risk exfiltration");
    }

    function test_postVerdict_noRiskFlagged_whenScoreLow() public {
        bytes32 intent = keccak256("pay coffee 3 usd");
        vm.recordLogs();
        oracle.postVerdict(agent, outsider, 0.01 ether, intent, 12, "benign");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        // VerdictPosted + no RiskFlagged: exactly 1 log
        assertEq(entries.length, 1);
    }

    function test_spend_ok_whenUnderLimit() public {
        bytes32 intent = keccak256("ok spend");
        uint256 before = outsider.balance;
        vm.prank(agent);
        vault.spend(payable(outsider), 0.05 ether, intent);
        assertEq(outsider.balance, before + 0.05 ether);
    }

    function test_spend_reverts_whenOverLimit() public {
        vm.prank(agent);
        vm.expectRevert(AgentVault.OverLimit.selector);
        vault.spend(payable(outsider), 0.2 ether, bytes32(0));
    }

    function test_spend_reverts_whenPaused() public {
        // Simulate callback proxy calling freeze
        vm.prank(PROXY);
        vault.freeze(reactive, keccak256("risk"));
        assertTrue(vault.paused());

        vm.prank(agent);
        vm.expectRevert(AgentVault.Paused.selector);
        vault.spend(payable(outsider), 0.01 ether, bytes32(0));
    }

    function test_freeze_reverts_forUnauthorizedSender() public {
        vm.prank(PROXY);
        vm.expectRevert();
        vault.freeze(makeAddr("evil"), bytes32(0));
    }

    function test_freeze_reverts_ifNotProxy() public {
        vm.prank(outsider);
        vm.expectRevert();
        vault.freeze(reactive, bytes32(0));
    }

    function test_topic0_matches() public pure {
        bytes32 t = keccak256("RiskFlagged(address,address,uint256,bytes32,uint8)");
        assertEq(
            t,
            bytes32(uint256(0x4d9695652967743f081c770dddf31932389fdfd01750fe347096e1edd86e90fe))
        );
    }
}
