//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { P2PLending } from "../contracts/P2PLending.sol";
import { UserRegistry } from "../contracts/UserRegistry.sol";
import { Reputation } from "../contracts/Reputation.sol";

/**
 * @notice Deployment script for P2PLending
 */
contract DeployP2PLending is ScaffoldETHDeploy {
    // This is run when this script is executed
    function run() external ScaffoldEthDeployerRunner returns (P2PLending) {
        // Get UserRegistry and Reputation addresses from deployments
        UserRegistry userRegistry = UserRegistry(_getDeploymentAddress("UserRegistry"));
        Reputation reputation = Reputation(_getDeploymentAddress("Reputation"));
        
        P2PLending p2pLending = new P2PLending(
            address(userRegistry),
            address(reputation),
            payable(deployer), // Use deployer as platform wallet
            address(0) // No cross-chain functionality for MVP
        );
        console.log("P2PLending deployed to:", address(p2pLending));

        // Set P2PLending address in Reputation contract
        reputation.setP2PLendingContractAddress(address(p2pLending));
        console.log("P2PLending address set in Reputation contract");

        deployments.push(
            Deployment({name: "P2PLending", addr: address(p2pLending)})
        );

        return p2pLending;
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