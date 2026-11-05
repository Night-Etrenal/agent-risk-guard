// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console2 } from "forge-std/Script.sol";
import { AIRiskOracle } from "../src/AIRiskOracle.sol";
import { AgentVault } from "../src/AgentVault.sol";
import { AgentGuardReactive } from "../src/AgentGuardReactive.sol";

/// @notice Multi-step deploy helpers. Prefer scripts/deploy.sh for full cross-chain flow.
contract DeployOracle is Script {
    function run() external payable {
        uint8 threshold = uint8(vm.envOr("THRESHOLD", uint256(70)));
        vm.startBroadcast();
        AIRiskOracle oracle = new AIRiskOracle(threshold);
        console2.log("AIRiskOracle", address(oracle));
        vm.stopBroadcast();
    }
}

contract DeployReactive is Script {
    function run() external payable {
        address oracle = vm.envAddress("ORACLE");
        uint256 topic0 = vm.envUint("RISK_TOPIC0");
        uint8 threshold = uint8(vm.envOr("THRESHOLD", uint256(70)));
        vm.startBroadcast();
        AgentGuardReactive reactive = new AgentGuardReactive{value: msg.value}(oracle, topic0, threshold);
        console2.log("AgentGuardReactive", address(reactive));
        vm.stopBroadcast();
    }
}

contract DeployVault is Script {
    function run() external payable {
        address proxy = vm.envAddress("CALLBACK_PROXY");
        address reactive = vm.envAddress("REACTIVE");
        address agent = vm.envAddress("AGENT");
        uint256 maxPerTx = vm.envOr("MAX_PER_TX", uint256(0.05 ether));
        vm.startBroadcast();
        AgentVault vault = new AgentVault{value: msg.value}(proxy, reactive, agent, maxPerTx);
        console2.log("AgentVault", address(vault));
        vm.stopBroadcast();
    }
}
