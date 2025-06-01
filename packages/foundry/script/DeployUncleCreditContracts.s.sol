//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { UserRegistry } from "../contracts/UserRegistry.sol";
import { Reputation } from "../contracts/Reputation.sol";
import { P2PLending } from "../contracts/P2PLending.sol";

/**
 * @notice Unified deployment script for all Uncle Credit contracts
 * @dev Deploys UserRegistry, Reputation, and P2PLending in sequence
 */
contract DeployUncleCreditContracts is ScaffoldETHDeploy {
    function run() external ScaffoldEthDeployerRunner {
        console.log("Starting Uncle Credit contracts deployment...");
        console.log("Deployer address:", deployer);

        // 1. Deploy UserRegistry (simplified - no World ID)
        console.log("Deploying UserRegistry...");
        UserRegistry userRegistry = new UserRegistry();
        console.log("UserRegistry deployed to:", address(userRegistry));
        deployments.push(
            Deployment({name: "UserRegistry", addr: address(userRegistry)})
        );

        // 2. Deploy Reputation Contract
        console.log("Deploying Reputation...");
        Reputation reputation = new Reputation(address(userRegistry));
        console.log("Reputation deployed to:", address(reputation));
        deployments.push(
            Deployment({name: "Reputation", addr: address(reputation)})
        );

        // 3. Deploy P2PLending Contract
        console.log("Deploying P2PLending...");
        P2PLending p2pLending = new P2PLending(
            address(userRegistry),
            address(reputation),
            payable(deployer), // Use deployer as platform wallet
            address(0) // No cross-chain functionality for MVP
        );
        console.log("P2PLending deployed to:", address(p2pLending));
        deployments.push(
            Deployment({name: "P2PLending", addr: address(p2pLending)})
        );

        // 4. Set P2P Lending contract address in Reputation contract
        console.log("Setting P2PLending address in Reputation contract...");
        reputation.setP2PLendingContractAddress(address(p2pLending));
        console.log("Configuration complete!");

        console.log("\n=== UNCLE CREDIT DEPLOYMENT SUMMARY ===");
        console.log("UserRegistry:  ", address(userRegistry));
        console.log("Reputation:    ", address(reputation));
        console.log("P2PLending:    ", address(p2pLending));
        console.log("=====================================");
    }
} 