// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";

/**
 * @title MockERC20
 * @dev Basic ERC20 mock token for testing purposes.
 *      Includes a mint function callable by the owner.
 */
contract MockERC20 is ERC20, Ownable {
    constructor(
        string memory name_,
        string memory symbol_,
        uint8 decimals_
    ) ERC20(name_, symbol_) Ownable(msg.sender) {
        // _setupDecimals(decimals_); // ERC20 constructor handles decimals if standard, or set manually if not through _setupDecimals
        // For standard ERC20, decimals are set via an internal _decimals variable.
        // If your ERC20 parent doesn't call _setupDecimals or similar, you might need to handle it or ensure your tests account for default decimals (18).
        // OpenZeppelin's ERC20 sets decimals to 18 by default if not overridden.
        // This constructor matches the OpenZeppelin ERC20 constructor which doesn't explicitly take decimals.
        // We will rely on the default of 18, or if an old OZ version is used, ensure it is set.
        // Modern OZ ERC20 does not have _setupDecimals and defaults to 18.
    }

    function mint(address to, uint256 amount) public onlyOwner {
        _mint(to, amount);
    }

    // In case the ERC20 parent contract has `decimals()` as virtual and we need to override:
    // function decimals() public view virtual override returns (uint8) {
    //     return 18; // Or whatever decimals you want for the mock
    // }
} 