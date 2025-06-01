//SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./DeployHelpers.s.sol";
import { DeployYourContract } from "./DeployYourContract.s.sol";
import { DeployUncleCreditContracts } from "./DeployUncleCreditContracts.s.sol";

/**
 * @notice Main deployment script for all contracts
 * @dev Run this when you want to deploy multiple contracts at once
 *
 * Example: yarn deploy # runs this script(without`--file` flag)
 */
contract DeployScript is ScaffoldETHDeploy {
    function run() external {
        // Deploy Uncle Credit contracts
        DeployUncleCreditContracts deployUncleCreditContracts = new DeployUncleCreditContracts();
        deployUncleCreditContracts.run();

        // Deploy example contract (can be removed later)
        // DeployYourContract deployYourContract = new DeployYourContract();
        // deployYourContract.run();

        // Deploy another contract
        // DeployMyContract myContract = new DeployMyContract();
        // myContract.run();
    }
}
