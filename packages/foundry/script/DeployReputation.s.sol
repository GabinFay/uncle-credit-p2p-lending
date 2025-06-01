//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { Reputation } from "../contracts/Reputation.sol";
import { UserRegistry } from "../contracts/UserRegistry.sol";

/**
 * @notice Deployment script for Reputation
 */
contract DeployReputation is ScaffoldETHDeploy {
    // This is run when this script is executed
    function run() external ScaffoldEthDeployerRunner returns (Reputation) {
        // Get UserRegistry address from deployments
        UserRegistry userRegistry = UserRegistry(_getDeploymentAddress("UserRegistry"));
        
        Reputation reputation = new Reputation(address(userRegistry));
        console.log("Reputation deployed to:", address(reputation));

        deployments.push(
            Deployment({name: "Reputation", addr: address(reputation)})
        );

        return reputation;
    }

    function _getDeploymentAddress(string memory contractName) internal view returns (address) {
        string memory root = vm.projectRoot();
        string memory path = string.concat(root, "/deployments/");
        string memory chainIdStr = vm.toString(block.chainid);
        path = string.concat(path, string.concat(chainIdStr, ".json"));
        
        string memory json = vm.readFile(path);
        return vm.parseJsonAddress(json, string.concat(".", contractName));
    }
} 