//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { UserRegistry } from "../contracts/UserRegistry.sol";

/**
 * @notice Deployment script for UserRegistry
 */
contract DeployUserRegistry is ScaffoldETHDeploy {
    // This is run when this script is executed
    function run() external ScaffoldEthDeployerRunner returns (UserRegistry) {
        UserRegistry userRegistry = new UserRegistry();
        console.log("UserRegistry deployed to:", address(userRegistry));

        deployments.push(
            Deployment({name: "UserRegistry", addr: address(userRegistry)})
        );

        return userRegistry;
    }
} 